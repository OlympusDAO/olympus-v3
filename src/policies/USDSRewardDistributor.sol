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

/// @title  USDS Reward Distributor
/// @notice Merkle tree-based rewards distribution for USDS rewards
/// @dev    This contract allows users to accumulate rewards based on their protocol activity
///         and claim rewards from a weekly Merkle tree distribution.
///
///         Architecture:
///         - Rewards are calculated off-chain
///         - Backend generates weekly merkle trees with accumulated rewards per user
///         - Merkle roots are posted on-chain by authorized role
///         - Users submit proofs to claim their rewards
contract USDSRewardDistributor is Policy, PolicyEnabler, IRewardDistributor {
    using TransferHelper for ERC20;

    /// @notice Role that can update merkle roots
    bytes32 public constant ROLE_MERKLE_UPDATER = "rewards_merkle_updater";

    /// @notice Minimum duration between week advances (7 days)
    uint256 public constant WEEK_DURATION = 7 days;

    /// @notice The TRSRY module
    TRSRYv1 internal TRSRY;

    /// @notice The reward token (immutable)
    ERC20 public immutable REWARD_TOKEN;

    /// @notice Mapping from week number => merkle root
    /// @dev    Week 0 is the first distribution week
    mapping(uint256 week => bytes32 merkleRoot) public weeklyMerkleRoots;

    /// @notice Mapping from user address => week number => claimed status
    mapping(address user => mapping(uint256 week => bool claimed)) public hasClaimed;

    /// @notice Timestamp when week 0 begins
    uint40 public immutable START_TIMESTAMP;

    modifier onlyAuthorized(bytes32 role_) {
        ROLES.requireRole(role_, msg.sender);
        _;
    }

    /// @param kernel_              The Kernel address
    /// @param rewardToken_         The ERC20 token to distribute as rewards
    /// @param startTimestamp_      The timestamp when week 0 begins (typically midnight UTC of start date)
    constructor(address kernel_, address rewardToken_, uint256 startTimestamp_) Policy(Kernel(kernel_)) {
        if (rewardToken_ == address(0)) revert DRD_InvalidAddress();
        if (startTimestamp_ == 0) revert DRD_InvalidAddress();
        REWARD_TOKEN = ERC20(rewardToken_);
        START_TIMESTAMP = uint40(startTimestamp_);
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

    /// @notice Set the merkle root for a week
    /// @dev    This function can only be called by addresses with the ROLE_MERKLE_UPDATER role.
    ///         Weeks can be set in any order (skipped weeks are allowed for distribution flexibility).
    ///         Calls are only allowed when the week deadline has been reached based on
    ///         the start timestamp and week number.
    ///
    ///         CRITICAL: Once a merkle root is set for a week, it cannot be changed. If an incorrect
    ///         root is set, the week will be locked with that root and users will be unable to claim
    ///         with the correct merkle proof. Ensure the merkle root is verified before calling this
    ///         function. If an error is discovered, a new distribution week will be required to distribute
    ///         the correct rewards.
    ///
    /// @param  week_          The week number being set
    /// @param  merkleRoot_     The merkle root for the week's distribution
    /// @return timestamp       The timestamp when the week ends
    function setMerkleRoot(
        uint40 week_,
        bytes32 merkleRoot_
    )
        external
        onlyAuthorized(ROLE_MERKLE_UPDATER)
        onlyEnabled
        returns (uint256 weekEndTime)
    {
        // Validate input
        if (merkleRoot_ == bytes32(0)) revert DRD_InvalidProof();

        // Ensure the week hasn't already been set
        if (weeklyMerkleRoots[week_] != bytes32(0)) revert DRD_WeekAlreadySet(week_);

        // Calculate when this week should end based on start timestamp and week number
        weekEndTime = START_TIMESTAMP + (week_ + 1) * WEEK_DURATION;

        // Ensure the current time has reached or passed the week deadline
        if (block.timestamp < weekEndTime) {
            revert DRD_WeekTooEarly();
        }

        // Set the merkle root for this week
        weeklyMerkleRoots[week_] = merkleRoot_;

        emit MerkleRootSet(week_, merkleRoot_, address(REWARD_TOKEN));
    }

    /// @notice Claim rewards for one or more weeks in a single transaction
    /// @dev    All weeks are claimed for the same reward token.
    ///
    /// @param  weeks_      Array of week numbers to claim
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

        uint256 totalAmount;

        for (uint256 i = 0; i < weeks_.length; ) {
            uint256 week = weeks_[i];
            uint256 amount = amounts_[i];

            // Verify merkle root is set for this week
            if (weeklyMerkleRoots[week] == bytes32(0)) revert DRD_MerkleRootNotSet(week);

            // Verify and mark as claimed
            _verifyAndMarkClaimed(msg.sender, week, amount, proofs_[i]);

            totalAmount += amount;

            unchecked {
                ++i;
            }
        }

        _transferRewards(msg.sender, totalAmount, weeks_.length);
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
    }

    /// @notice Internal function to transfer rewards from treasury and update accounting
    /// @param  to_         Address to transfer rewards to
    /// @param  amount_     Amount to transfer
    /// @param  weekCount_  Number of weeks being claimed (for event)
    function _transferRewards(
        address to_,
        uint256 amount_,
        uint256 weekCount_
    ) internal {
        // Early return if no amount to transfer
        if (amount_ == 0) return;

        // Increase withdrawal approval and withdraw from treasury
        // This requires that this policy has been granted the appropriate permissions
        TRSRY.increaseWithdrawApproval(address(this), REWARD_TOKEN, amount_);
        TRSRY.withdrawReserves(to_, REWARD_TOKEN, amount_);

        // Emit rewards claimed event with week count
        emit RewardsClaimed(to_, amount_, address(REWARD_TOKEN), weekCount_);
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
