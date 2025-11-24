// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

// Libraries
import {MerkleProof} from "@openzeppelin-5.3.0/utils/cryptography/MerkleProof.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title  Base Reward Distributor
/// @notice Abstract base contract for Merkle tree-based rewards distribution
/// @dev    Architecture:
///         - Rewards are calculated off-chain
///         - Backend generates weekly Merkle trees with accumulated rewards per user
///         - Merkle roots are posted on-chain by authorized role
///         - Users submit proofs to claim their rewards
abstract contract BaseRewardDistributor is Policy, PolicyEnabler, IRewardDistributor {
    // ========== STATE VARIABLES ========== //

    /// @notice Role that can update merkle roots
    bytes32 public constant ROLE_MERKLE_UPDATER = "rewards_merkle_updater";

    /// @notice Minimum duration between week advances
    uint256 public constant WEEK_DURATION = 7 days;

    /// @notice The TRSRY module
    TRSRYv1 internal TRSRY;

    /// @notice The reward token
    IERC20 public immutable REWARD_TOKEN;

    /// @notice The reward token vault
    IERC4626 public immutable REWARD_TOKEN_VAULT;

    /// @notice Mapping from week number => merkle root
    /// @dev    Week 0 is the first distribution week
    mapping(uint256 week => bytes32 merkleRoot) public weeklyMerkleRoots;

    /// @notice Mapping from user address => week number => claimed status
    mapping(address user => mapping(uint256 week => bool claimed)) public hasClaimed;

    /// @notice Timestamp when week 0 begins
    uint40 public immutable START_TIMESTAMP;

    // ========== MODIFIERS ========== //

    modifier onlyAuthorized(bytes32 role_) {
        ROLES.requireRole(role_, msg.sender);
        _;
    }

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructor
    ///
    /// @param  kernel_             The Kernel address
    /// @param  rewardTokenVault_   The ERC4626 vault token
    /// @param  startTimestamp_     The timestamp when week 0 begins (midnight UTC of start date)
    constructor(
        address kernel_,
        address rewardTokenVault_,
        uint256 startTimestamp_
    ) Policy(Kernel(kernel_)) {
        if (rewardTokenVault_ == address(0)) revert RewardDistributor_InvalidAddress();
        if (startTimestamp_ == 0) revert RewardDistributor_InvalidAddress();
        REWARD_TOKEN = IERC20(IERC4626(rewardTokenVault_).asset());
        REWARD_TOKEN_VAULT = IERC4626(rewardTokenVault_);
        START_TIMESTAMP = uint40(startTimestamp_);
        // Disabled by default by PolicyEnabler
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");

        // ROLES is inherited from PolicyEnabler
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        virtual
        override
        returns (Permissions[] memory permissions)
    {
        Keycode trsryKeycode = toKeycode("TRSRY");

        permissions = new Permissions[](1);
        permissions[0] = Permissions(trsryKeycode, TRSRY.withdrawReserves.selector);
    }

    function VERSION() external pure virtual returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
        return (major, minor);
    }

    // ========== MERKLE ROOT MANAGEMENT ========== //

    /// @notice Set the Merkle root for a week
    /// @dev    - Only callable by the ROLE_MERKLE_UPDATER role
    ///         - Weeks can be set in any order
    ///         - Calls are only allowed when the week deadline has been reached
    ///         - Merkle tree cannot be updated once set
    ///
    /// @param  week_           The week number being set
    /// @param  merkleRoot_     The Merkle root for the week's distribution
    /// @return weekEndTime     The timestamp when the week ends
    function setMerkleRoot(
        uint40 week_,
        bytes32 merkleRoot_
    )
        external
        virtual
        onlyAuthorized(ROLE_MERKLE_UPDATER)
        onlyEnabled
        returns (uint256 weekEndTime)
    {
        // Validate input
        if (merkleRoot_ == bytes32(0)) revert RewardDistributor_InvalidProof();

        // Ensure the week hasn't already been set
        if (weeklyMerkleRoots[week_] != bytes32(0)) revert RewardDistributor_WeekAlreadySet(week_);

        // Calculate when this week should end based on start timestamp and week number
        weekEndTime = START_TIMESTAMP + (week_ + 1) * WEEK_DURATION;

        // Ensure the current time has reached or passed the week deadline
        if (block.timestamp < weekEndTime) {
            revert RewardDistributor_WeekTooEarly();
        }

        // Set the merkle root for this week
        weeklyMerkleRoots[week_] = merkleRoot_;

        _emitMerkleRootSet(week_, merkleRoot_);
    }

    // ========== CLAIM FUNCTIONS ========== //

    /// @notice Preview the claimable rewards for a user without claiming
    /// @dev    Returns 0 amounts if no valid claims are found (Merkle root not set or proof invalid)
    ///
    /// @param  user_               The user address to preview claims for
    /// @param  claimWeeks_         Array of week numbers to preview
    /// @param  amounts_            Array of amounts for each week (must match Merkle leaves)
    /// @param  proofs_             Array of Merkle proofs, one per week
    /// @return claimableAmount     The total amount of reward token claimable
    /// @return vaultShares         The amount of vault shares equivalent to the claimable amount
    function previewClaim(
        address user_,
        uint256[] calldata claimWeeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external view returns (uint256 claimableAmount, uint256 vaultShares) {
        // Validate array lengths, return 0 if invalid
        if (
            claimWeeks_.length == 0 ||
            claimWeeks_.length != amounts_.length ||
            claimWeeks_.length != proofs_.length
        ) {
            return (0, 0);
        }

        for (uint256 i = 0; i < claimWeeks_.length; ) {
            uint256 week = claimWeeks_[i];
            uint256 amount = amounts_[i];

            // Skip weeks without merkle roots set
            if (weeklyMerkleRoots[week] != bytes32(0)) {
                // Verify proof safely, skip if invalid or already claimed
                if (_verifyProofSafe(user_, week, amount, proofs_[i])) {
                    claimableAmount += amount;
                }
            }

            unchecked {
                ++i;
            }
        }

        // Calculate equivalent vault shares
        if (claimableAmount > 0) {
            vaultShares = REWARD_TOKEN_VAULT.previewWithdraw(claimableAmount);
        }
    }

    /// @notice Claim rewards for one or more weeks in a single transaction
    ///
    /// @param  weeks_          Array of week numbers to claim
    /// @param  amounts_        Array of amounts for each week (must match Merkle leaves)
    /// @param  proofs_         Array of Merkle proofs, one per week
    /// @param  asVaultToken_   If true, claim as vault token; if false, unwrap to underlying token
    function claim(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_,
        bool asVaultToken_
    ) external virtual onlyEnabled {
        _validateClaimArrays(weeks_, amounts_, proofs_);

        uint256 totalAmount = _processClaims(msg.sender, weeks_, amounts_, proofs_);

        _transferRewards(msg.sender, totalAmount, weeks_.length, asVaultToken_);
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Validate claim input arrays
    ///
    /// @param  weeks_          Array of week numbers to claim
    /// @param  amounts_        Array of amounts for each week
    /// @param  proofs_         Array of Merkle proofs, one per week
    function _validateClaimArrays(
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) internal pure {
        if (weeks_.length == 0) revert RewardDistributor_NoWeeksSpecified();
        if (weeks_.length != amounts_.length || weeks_.length != proofs_.length) {
            revert RewardDistributor_ArrayLengthMismatch();
        }
    }

    /// @notice Process claims and return total amount
    ///
    /// @param  user_           The user address claiming rewards
    /// @param  weeks_          Array of week numbers to claim
    /// @param  amounts_        Array of amounts for each week
    /// @param  proofs_         Array of Merkle proofs, one per week
    /// @return totalAmount     The total amount claimed across all weeks
    function _processClaims(
        address user_,
        uint256[] calldata weeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) internal returns (uint256 totalAmount) {
        for (uint256 i = 0; i < weeks_.length; ) {
            uint256 week = weeks_[i];
            uint256 amount = amounts_[i];

            // Verify merkle root is set for this week
            if (weeklyMerkleRoots[week] == bytes32(0))
                revert RewardDistributor_MerkleRootNotSet(week);

            // Verify and mark as claimed
            _verifyAndMarkClaimed(user_, week, amount, proofs_[i]);

            totalAmount += amount;

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Verify Merkle proof without modifying state
    ///
    /// @param  user_           The user address
    /// @param  week_           The week number
    /// @param  amount_         The amount to verify
    /// @param  proof_          The Merkle proof
    function _verifyProof(
        address user_,
        uint256 week_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal view virtual {
        // Check if already claimed
        if (hasClaimed[user_][week_]) revert RewardDistributor_AlreadyClaimed(week_);

        // Construct the leaf node: keccak256(abi.encode(user, week, amount))
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user_, week_, amount_))));

        // Verify Merkle proof
        if (!MerkleProof.verify(proof_, weeklyMerkleRoots[week_], leaf)) {
            revert RewardDistributor_InvalidProof();
        }
    }

    /// @notice Verify Merkle proof without reverting on failure
    ///
    /// @param  user_           The user address
    /// @param  week_           The week number
    /// @param  amount_         The amount to verify
    /// @param  proof_          The Merkle proof
    /// @return isValid         True if proof is valid and claimable, false otherwise
    function _verifyProofSafe(
        address user_,
        uint256 week_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal view virtual returns (bool isValid) {
        // Check if already claimed
        if (hasClaimed[user_][week_]) return false;

        // Construct the leaf node: keccak256(abi.encode(user, week, amount))
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user_, week_, amount_))));

        // Verify Merkle proof and return result
        return MerkleProof.verify(proof_, weeklyMerkleRoots[week_], leaf);
    }

    /// @notice Verify Merkle proof and mark week as claimed for user
    ///
    /// @param  user_           The user address
    /// @param  week_           The week number
    /// @param  amount_         The amount to verify
    /// @param  proof_          The Merkle proof
    function _verifyAndMarkClaimed(
        address user_,
        uint256 week_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal virtual {
        // Verify proof first
        _verifyProof(user_, week_, amount_, proof_);

        // Mark as claimed
        hasClaimed[user_][week_] = true;
    }

    /// @notice Internal function to transfer rewards from treasury
    /// @dev    Must be implemented by derived contracts
    ///
    /// @param  to_             Address to transfer rewards to
    /// @param  amount_         Amount to transfer
    /// @param  weekCount_      Number of weeks being claimed (for event)
    /// @param  asVaultToken_   If true, transfer as vault token; if false, unwrap first
    function _transferRewards(
        address to_,
        uint256 amount_,
        uint256 weekCount_,
        bool asVaultToken_
    ) internal virtual;

    /// @notice Emit Merkle root set event
    ///
    /// @param  week_           The week number
    /// @param  merkleRoot_     The Merkle root
    function _emitMerkleRootSet(uint256 week_, bytes32 merkleRoot_) internal {
        emit MerkleRootSet(week_, merkleRoot_, address(REWARD_TOKEN));
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
