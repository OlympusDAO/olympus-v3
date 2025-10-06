// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IOlympusPointsDistributor} from "../interfaces/IOlympusPointsDistributor.sol";
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

/// @title  Olympus Points Distributor
/// @notice Merkle tree-based rewards distribution for Olympus Points program
/// @dev    This contract allows users to accumulate points based on their convertible deposit positions
///         and claim rewards from a weekly Merkle tree distribution. Users can claim multiple weeks
///         in a single transaction for gas efficiency.
///
///         Key Features:
///         - Off-chain points calculation with on-chain verification via Merkle proofs
///         - Weekly merkle root updates by authorized updaters
///         - Multi-week batch claiming to reduce gas costs
///         - Emergency pause functionality
///         - Rewards paid from treasury (typically USDS from yield generation)
///
///         Architecture:
///         - Points are calculated off-chain based on deposit amount × time held
///         - Backend generates weekly merkle trees with accumulated points per user
///         - Merkle roots are posted on-chain by authorized role (typically multisig or automated keeper)
///         - Users submit proofs to claim their rewards
///
contract OlympusPointsDistributor is Policy, PolicyEnabler, IOlympusPointsDistributor {
    using TransferHelper for ERC20;

    // ========== STATE VARIABLES ========== //

    /// @notice The TRSRY module
    TRSRYv1 internal TRSRY;

    /// @notice Role that can update merkle roots
    bytes32 public constant ROLE_MERKLE_UPDATER = "points_merkle_updater";

    /// @notice Role that can update reward tokens
    bytes32 public constant ROLE_REWARDS_ADMIN = "points_rewards_admin";

    /// @notice Mapping from week number => merkle root
    /// @dev    Week 0 is the first distribution week
    mapping(uint256 week => bytes32 merkleRoot) public weeklyMerkleRoots;

    /// @notice Mapping from user address => week number => claimed status
    mapping(address user => mapping(uint256 week => bool claimed)) public hasClaimed;

    /// @notice Mapping from week number => reward token address
    /// @dev    Allows different reward tokens for different weeks (e.g., USDS, DAI, etc.)
    mapping(uint256 week => address rewardToken) public weeklyRewardTokens;

    /// @notice The current week number
    uint256 public currentWeek;

    /// @notice Total rewards claimed by each user (in reward token decimals)
    mapping(address user => mapping(address token => uint256 amount)) public totalClaimed;

    /// @notice Total rewards distributed per week
    mapping(uint256 week => uint256 amount) public weeklyRewardsDistributed;

    /// @notice Mapping from week number => metadata IPFS hash
    /// @dev    Points to off-chain data containing full distribution details
    mapping(uint256 week => string ipfsHash) public weeklyMetadata;

    // ========== MODIFIERS ========== //

    modifier onlyAuthorized(bytes32 role_) {
        ROLES.requireRole(role_, msg.sender);
        _;
    }

    // ========== SETUP ========== //

    constructor(address kernel_) Policy(Kernel(kernel_)) {
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

    /// @notice Set the merkle root for a specific week
    /// @dev    This function can only be called by addresses with the ROLE_MERKLE_UPDATER role
    ///         Typically called by a multisig or automated keeper after off-chain calculation
    ///
    /// @param  week_           The week number to set the merkle root for
    /// @param  merkleRoot_     The merkle root for the week's distribution
    /// @param  rewardToken_    The ERC20 token used for rewards this week
    /// @param  ipfsHash_       IPFS hash containing full distribution data for transparency
    function setMerkleRoot(
        uint256 week_,
        bytes32 merkleRoot_,
        address rewardToken_,
        string calldata ipfsHash_
    ) external onlyAuthorized(ROLE_MERKLE_UPDATER) onlyEnabled {
        // Validate inputs
        if (merkleRoot_ == bytes32(0)) revert OPD_InvalidProof();
        if (rewardToken_ == address(0)) revert OPD_InvalidAddress();

        // Allow setting roots for current week or future weeks, but not past weeks
        // This prevents accidentally overwriting historical data
        if (week_ < currentWeek) revert OPD_InvalidWeek(week_);

        // Set the merkle root
        weeklyMerkleRoots[week_] = merkleRoot_;
        weeklyRewardTokens[week_] = rewardToken_;
        weeklyMetadata[week_] = ipfsHash_;

        emit MerkleRootSet(week_, merkleRoot_, rewardToken_, ipfsHash_);
    }

    /// @notice Set merkle roots for multiple weeks in one transaction
    /// @dev    Gas-efficient way to set multiple weeks at once
    ///
    /// @param  weeks_          Array of week numbers
    /// @param  merkleRoots_    Array of merkle roots
    /// @param  rewardTokens_   Array of reward token addresses
    /// @param  ipfsHashes_     Array of IPFS hashes
    function setMerkleRootBatch(
        uint256[] calldata weeks_,
        bytes32[] calldata merkleRoots_,
        address[] calldata rewardTokens_,
        string[] calldata ipfsHashes_
    ) external onlyAuthorized(ROLE_MERKLE_UPDATER) onlyEnabled {
        uint256 length = weeks_.length;
        if (
            length != merkleRoots_.length ||
            length != rewardTokens_.length ||
            length != ipfsHashes_.length
        ) revert OPD_ArrayLengthMismatch();

        if (length == 0) revert OPD_NoWeeksSpecified();

        for (uint256 i = 0; i < length; ) {
            uint256 week = weeks_[i];
            bytes32 root = merkleRoots_[i];
            address token = rewardTokens_[i];
            string calldata ipfsHash = ipfsHashes_[i];

            if (root == bytes32(0)) revert OPD_InvalidProof();
            if (token == address(0)) revert OPD_InvalidAddress();
            if (week < currentWeek) revert OPD_InvalidWeek(week);

            weeklyMerkleRoots[week] = root;
            weeklyRewardTokens[week] = token;
            weeklyMetadata[week] = ipfsHash;

            emit MerkleRootSet(week, root, token, ipfsHash);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Advance to the next week
    /// @dev    This is called by the updater role to signal progression to a new week
    ///         Not strictly necessary for functionality, but useful for tracking
    function advanceWeek() external onlyAuthorized(ROLE_MERKLE_UPDATER) onlyEnabled {
        currentWeek++;
        emit WeekAdvanced(currentWeek);
    }

    /// @notice Update the reward token for a future week
    /// @dev    Allows changing the reward token before the merkle root is set
    ///         Cannot modify past weeks to preserve historical accuracy
    ///
    /// @param  week_           The week to update
    /// @param  rewardToken_    The new reward token address
    function updateRewardToken(
        uint256 week_,
        address rewardToken_
    ) external onlyAuthorized(ROLE_REWARDS_ADMIN) onlyEnabled {
        if (week_ < currentWeek) revert OPD_InvalidWeek(week_);
        if (rewardToken_ == address(0)) revert OPD_InvalidAddress();

        address oldToken = weeklyRewardTokens[week_];
        weeklyRewardTokens[week_] = rewardToken_;

        emit RewardTokenUpdated(week_, oldToken, rewardToken_);
    }

    // ========== CLAIMING ========== //

    /// @notice Claim rewards for a single week
    /// @dev    This function verifies the merkle proof and transfers rewards to the caller
    ///
    /// @param  week_       The week to claim rewards for
    /// @param  amount_     The amount of rewards to claim (must match merkle leaf)
    /// @param  proof_      The merkle proof
    function claimWeek(
        uint256 week_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) external onlyEnabled {
        _claimWeek(msg.sender, week_, amount_, proof_);
    }

    /// @notice Claim rewards for multiple weeks in one transaction
    /// @dev    This is the recommended way to claim to save gas
    ///         All weeks must use the same reward token
    ///
    /// @param  weeks_      Array of week numbers to claim
    /// @param  amounts_    Array of amounts for each week (must match merkle leaves)
    /// @param  proofs_     Array of merkle proofs, one per week
    function claimMultipleWeeks(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external onlyEnabled {
        if (weeks_.length == 0) revert OPD_NoWeeksSpecified();
        if (weeks_.length != amounts_.length || weeks_.length != proofs_.length) {
            revert OPD_ArrayLengthMismatch();
        }

        // Track total amount per token
        address rewardToken;
        uint256 totalAmount;

        for (uint256 i = 0; i < weeks_.length; ) {
            uint256 week = weeks_[i];
            uint256 amount = amounts_[i];

            // Get the reward token for this week
            address weekToken = weeklyRewardTokens[week];
            if (weekToken == address(0)) revert OPD_MerkleRootNotSet(week);

            // Ensure all weeks use the same token for this batch
            if (i == 0) {
                rewardToken = weekToken;
            } else if (weekToken != rewardToken) {
                revert OPD_InvalidWeek(week);
            }

            // Verify and mark as claimed
            _verifyAndMarkClaimed(msg.sender, week, amount, proofs_[i]);

            totalAmount += amount;

            unchecked {
                ++i;
            }
        }

        // Transfer the total amount
        if (totalAmount > 0) {
            _transferRewards(msg.sender, rewardToken, totalAmount);

            // Update user's total claimed
            totalClaimed[msg.sender][rewardToken] += totalAmount;
        }

        emit RewardsClaimed(msg.sender, totalAmount, rewardToken, weeks_.length);
    }

    /// @notice Claim rewards for multiple weeks with different reward tokens
    /// @dev    Used when claiming across weeks that have different reward tokens
    ///         Groups claims by token internally for efficient transfers
    ///
    /// @param  weeks_      Array of week numbers to claim
    /// @param  amounts_    Array of amounts for each week
    /// @param  proofs_     Array of merkle proofs
    function claimMultipleWeeksMultiToken(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external onlyEnabled {
        if (weeks_.length == 0) revert OPD_NoWeeksSpecified();
        if (weeks_.length != amounts_.length || weeks_.length != proofs_.length) {
            revert OPD_ArrayLengthMismatch();
        }

        // We'll accumulate amounts per token in memory
        // For simplicity, we use a maximum of 2 different tokens per batch
        address token1;
        address token2;
        uint256 amount1;
        uint256 amount2;

        for (uint256 i = 0; i < weeks_.length; ) {
            uint256 week = weeks_[i];
            uint256 amount = amounts_[i];

            // Get the reward token for this week
            address weekToken = weeklyRewardTokens[week];
            if (weekToken == address(0)) revert OPD_MerkleRootNotSet(week);

            // Verify and mark as claimed
            _verifyAndMarkClaimed(msg.sender, week, amount, proofs_[i]);

            // Accumulate by token
            if (token1 == address(0)) {
                token1 = weekToken;
                amount1 += amount;
            } else if (weekToken == token1) {
                amount1 += amount;
            } else if (token2 == address(0)) {
                token2 = weekToken;
                amount2 += amount;
            } else if (weekToken == token2) {
                amount2 += amount;
            } else {
                // More than 2 tokens in a single batch is not supported
                // Users should split into multiple transactions
                revert OPD_InvalidWeek(week);
            }

            unchecked {
                ++i;
            }
        }

        // Transfer accumulated amounts
        if (amount1 > 0) {
            _transferRewards(msg.sender, token1, amount1);
            totalClaimed[msg.sender][token1] += amount1;
        }
        if (amount2 > 0) {
            _transferRewards(msg.sender, token2, amount2);
            totalClaimed[msg.sender][token2] += amount2;
        }

        emit RewardsClaimed(msg.sender, amount1 + amount2, token1, weeks_.length);
    }

    /// @notice Internal function to claim a single week
    function _claimWeek(
        address user_,
        uint256 week_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal {
        // Verify and mark as claimed
        _verifyAndMarkClaimed(user_, week_, amount_, proof_);

        // Get the reward token for this week
        address rewardToken = weeklyRewardTokens[week_];
        if (rewardToken == address(0)) revert OPD_MerkleRootNotSet(week_);

        // Transfer rewards
        if (amount_ > 0) {
            _transferRewards(user_, rewardToken, amount_);

            // Update user's total claimed
            totalClaimed[user_][rewardToken] += amount_;
        }

        emit RewardsClaimed(user_, amount_, rewardToken, 1);
    }

    /// @notice Verify merkle proof and mark week as claimed for user
    function _verifyAndMarkClaimed(
        address user_,
        uint256 week_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal {
        // Check if already claimed
        if (hasClaimed[user_][week_]) revert OPD_AlreadyClaimed(week_);

        // Get the merkle root for this week
        bytes32 merkleRoot = weeklyMerkleRoots[week_];
        if (merkleRoot == bytes32(0)) revert OPD_MerkleRootNotSet(week_);

        // Construct the leaf node: keccak256(abi.encode(user, week, amount))
        // We include week in the leaf to prevent replay attacks across weeks
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user_, week_, amount_))));

        // Verify the merkle proof
        if (!MerkleProof.verify(proof_, merkleRoot, leaf)) revert OPD_InvalidProof();

        // Mark as claimed
        hasClaimed[user_][week_] = true;

        // Track distributed amount for this week
        weeklyRewardsDistributed[week_] += amount_;
    }

    /// @notice Internal function to transfer rewards from treasury
    function _transferRewards(address to_, address token_, uint256 amount_) internal {
        if (amount_ == 0) revert OPD_ZeroAmount();

        // Increase withdrawal approval and withdraw from treasury
        // This requires that this policy has been granted the appropriate permissions
        TRSRY.increaseWithdrawApproval(address(this), ERC20(token_), amount_);
        TRSRY.withdrawReserves(to_, ERC20(token_), amount_);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Check if a user has claimed for a specific week
    function hasUserClaimedWeek(address user_, uint256 week_) external view returns (bool) {
        return hasClaimed[user_][week_];
    }

    /// @notice Get the merkle root for a specific week
    function getMerkleRoot(uint256 week_) external view returns (bytes32) {
        return weeklyMerkleRoots[week_];
    }

    /// @notice Get the reward token for a specific week
    function getRewardToken(uint256 week_) external view returns (address) {
        return weeklyRewardTokens[week_];
    }

    /// @notice Get total amount claimed by a user for a specific token
    function getTotalClaimed(address user_, address token_) external view returns (uint256) {
        return totalClaimed[user_][token_];
    }

    /// @notice Get total rewards distributed for a specific week
    function getWeeklyDistributed(uint256 week_) external view returns (uint256) {
        return weeklyRewardsDistributed[week_];
    }

    /// @notice Get metadata IPFS hash for a specific week
    function getWeeklyMetadata(uint256 week_) external view returns (string memory) {
        return weeklyMetadata[week_];
    }

    /// @notice Preview if a claim would be valid (doesn't check proof validity)
    function previewClaim(
        address user_,
        uint256 week_
    ) external view returns (bool canClaim, string memory reason) {
        if (hasClaimed[user_][week_]) {
            return (false, "Already claimed");
        }

        if (weeklyMerkleRoots[week_] == bytes32(0)) {
            return (false, "Merkle root not set");
        }

        if (!isEnabled) {
            return (false, "Contract disabled");
        }

        return (true, "");
    }

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId) public view virtual override(PolicyEnabler, IERC165) returns (bool) {
        return
            interfaceId == type(IOlympusPointsDistributor).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}

