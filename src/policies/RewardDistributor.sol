// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";

// Libraries
import {MerkleProof} from "@openzeppelin-5.3.0/utils/cryptography/MerkleProof.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title  Reward Distributor
/// @notice Merkle tree-based rewards distribution
/// @dev    This contract allows users to accumulate rewards based on their protocol activity
///         and claim rewards from a weekly Merkle tree distribution.
///
///         Architecture:
///         - Rewards are calculated off-chain
///         - Backend generates weekly merkle trees with accumulated rewards per user
///         - Merkle roots are posted on-chain by authorized role
///         - Users submit proofs to claim their rewards
contract RewardDistributor is Policy, PolicyEnabler, IRewardDistributor {
    using TransferHelper for ERC20;

    /// @notice Role that can update merkle roots
    bytes32 public constant ROLE_MERKLE_UPDATER = "rewards_merkle_updater";

    /// @notice Minimum duration between week advances (7 days)
    uint256 public constant WEEK_DURATION = 7 days;

    /// @notice The TRSRY module
    TRSRYv1 internal TRSRY;

    /// @notice Mapping from week number => merkle root
    /// @dev    Week 0 is the first distribution week
    mapping(uint256 week => bytes32 merkleRoot) public weeklyMerkleRoots;

    /// @notice Mapping from week number => reward token address
    /// @dev    Allows different reward tokens for different weeks (e.g., USDS, DAI, etc.)
    mapping(uint256 week => address rewardToken) public weeklyRewardTokens;

    /// @notice Total rewards distributed per week
    mapping(uint256 week => uint256 amount) public weeklyRewardsDistributed;

    /// @notice Mapping from user address => week number => claimed status
    mapping(address user => mapping(uint256 week => bool claimed)) public hasClaimed;

    /// @notice Total rewards claimed by each user (in reward token decimals)
    mapping(address user => mapping(address token => uint256 amount)) public totalClaimed;

    /// @notice The current week number
    uint40 public currentWeek;

    /// @notice Timestamp when week 0 begins
    uint40 public immutable startTimestamp;

    modifier onlyAuthorized(bytes32 role_) {
        ROLES.requireRole(role_, msg.sender);
        _;
    }

    /// @param kernel_              The Kernel address
    /// @param startTimestamp_      The timestamp when week 0 begins (typically midnight UTC of start date)
    constructor(address kernel_, uint256 startTimestamp_) Policy(Kernel(kernel_)) {
        if (startTimestamp_ == 0) revert DRD_InvalidAddress();
        startTimestamp = uint40(startTimestamp_);
        // Disabled by default by PolicyEnabler
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode trsryKeycode = toKeycode("TRSRY");

        permissions = new Permissions[](2);
        permissions[0] = Permissions(trsryKeycode, TRSRY.increaseWithdrawApproval.selector);
        permissions[1] = Permissions(trsryKeycode, TRSRY.withdrawReserves.selector);
    }

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
        return (major, minor);
    }

    // ========== MERKLE ROOT MANAGEMENT ========== //

    /// @notice Set the merkle root for the current week
    /// @dev    This function can only be called by addresses with the ROLE_MERKLE_UPDATER role.
    ///         Calls are only allowed when the current week deadline has been reached based on
    ///         the start timestamp and week number. The function automatically advances to the next week.
    ///
    /// @param  rewardWeek_     The week number being set (must equal currentWeek)
    /// @param  merkleRoot_     The merkle root for the week's distribution
    /// @param  rewardToken_    The ERC20 token used for rewards this week
    /// @return week            The week number that was set
    /// @return timestamp       The timestamp when the current week ends
    function setMerkleRoot(
        uint40 rewardWeek_,
        bytes32 merkleRoot_,
        address rewardToken_
    )
        external
        onlyAuthorized(ROLE_MERKLE_UPDATER)
        onlyEnabled
        returns (uint256 week, uint256 timestamp)
    {
        // Validate inputs
        if (merkleRoot_ == bytes32(0)) revert DRD_InvalidProof();
        if (rewardToken_ == address(0)) revert DRD_InvalidAddress();

        // Cache storage variables to save gas
        week = currentWeek;

        // Ensure the passed rewardWeek matches the current week
        if (rewardWeek_ != week) revert DRD_InvalidWeek(rewardWeek_);

        // Calculate when the current week should end based on start timestamp and week number
        uint256 weekEndTime = startTimestamp + (week + 1) * WEEK_DURATION;

        // Ensure the current time has reached or passed the week deadline
        if (block.timestamp < weekEndTime) {
            revert DRD_WeekTooEarly();
        }

        // Set the merkle root for the current week
        weeklyMerkleRoots[week] = merkleRoot_;
        weeklyRewardTokens[week] = rewardToken_;

        // Calculate the timestamp when this week ends
        timestamp = weekEndTime;

        emit MerkleRootSet(week, merkleRoot_, rewardToken_);

        // Advance to next week for the next call
        currentWeek = uint40(week + 1);
    }

    /// @notice Claim rewards for one or more weeks in a single transaction
    /// @dev    This function handles both single week and multi-week claims.
    ///         For single week: pass arrays of length 1.
    ///         For multiple weeks: automatically handles different reward tokens (up to 2).
    ///
    /// @param  weeks_      Array of week numbers to claim (can be length 1 for single week)
    /// @param  amounts_    Array of amounts for each week (must match merkle leaves)
    /// @param  proofs_     Array of merkle proofs, one per week
    function claim(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external onlyEnabled {
        if (weeks_.length == 0) revert DRD_NoWeeksSpecified();
        if (weeks_.length != amounts_.length || weeks_.length != proofs_.length) {
            revert DRD_ArrayLengthMismatch();
        }

        address token1;
        address token2;
        uint256 amount1;
        uint256 amount2;
        uint256 weeksForToken1;
        uint256 weeksForToken2;

        for (uint256 i = 0; i < weeks_.length; ) {
            uint256 week = weeks_[i];
            uint256 amount = amounts_[i];

            // Get the reward token for this week
            address weekToken = weeklyRewardTokens[week];
            if (weekToken == address(0)) revert DRD_MerkleRootNotSet(week);

            // Verify and mark as claimed
            _verifyAndMarkClaimed(msg.sender, week, amount, proofs_[i]);

            // Accumulate by token and count weeks
            if (token1 == address(0)) {
                token1 = weekToken;
                amount1 += amount;
                weeksForToken1++;
            } else if (weekToken == token1) {
                amount1 += amount;
                weeksForToken1++;
            } else if (token2 == address(0)) {
                token2 = weekToken;
                amount2 += amount;
                weeksForToken2++;
            } else if (weekToken == token2) {
                amount2 += amount;
                weeksForToken2++;
            } else {
                // More than 2 tokens in a single batch is not supported
                // Users should split into multiple transactions
                revert DRD_InvalidWeek(week);
            }

            unchecked {
                ++i;
            }
        }

        _transferRewards(msg.sender, token1, amount1, weeksForToken1);
        _transferRewards(msg.sender, token2, amount2, weeksForToken2);
    }

    /// @notice Verify merkle proof and mark week as claimed for user
    function _verifyAndMarkClaimed(
        address user_,
        uint256 week_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal {
        // Check if already claimed
        if (hasClaimed[user_][week_]) revert DRD_AlreadyClaimed(week_);

        // Construct the leaf node: keccak256(abi.encode(user, week, amount))
        // Week is included in the leaf to prevent replay attacks across weeks
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user_, week_, amount_))));

        // Verify merkle proof (week validity already checked by caller)
        if (!MerkleProof.verify(proof_, weeklyMerkleRoots[week_], leaf)) {
            revert DRD_InvalidProof();
        }

        hasClaimed[user_][week_] = true;
        weeklyRewardsDistributed[week_] += amount_;
    }

    /// @notice Internal function to transfer rewards from treasury and update accounting
    /// @param  to_         Address to transfer rewards to
    /// @param  token_      Reward token address
    /// @param  amount_     Amount to transfer
    /// @param  weekCount_  Number of weeks being claimed for this token (for event)
    function _transferRewards(
        address to_,
        address token_,
        uint256 amount_,
        uint256 weekCount_
    ) internal {
        // Early return if no amount to transfer
        if (amount_ == 0) return;

        // Increase withdrawal approval and withdraw from treasury
        // This requires that this policy has been granted the appropriate permissions
        TRSRY.increaseWithdrawApproval(address(this), ERC20(token_), amount_);
        TRSRY.withdrawReserves(to_, ERC20(token_), amount_);

        // Update total claimed tracking
        totalClaimed[to_][token_] += amount_;

        // Emit rewards claimed event
        emit RewardsClaimed(to_, amount_, token_, weekCount_);
    }

    // ========== ERC165 ========== //

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(PolicyEnabler, IERC165) returns (bool) {
        return
            interfaceId == type(IRewardDistributor).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
