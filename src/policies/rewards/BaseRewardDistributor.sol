// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

// Interfaces
import {IRewardDistributor} from "src/policies/interfaces/rewards/IRewardDistributor.sol";
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";

// Libraries
import {MerkleProof} from "@openzeppelin-5.3.0/utils/cryptography/MerkleProof.sol";

// Bophades
import {Kernel, Keycode, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title Base Reward Distributor
/// @notice Minimal abstract base contract for Merkle tree-based rewards distribution.
/// @dev Architecture:
///      - Provides internal building blocks for epoch and merkle management.
///      - Derived contracts define their own public API.
///      - No assumptions about reward token type.
abstract contract BaseRewardDistributor is Policy, PolicyEnabler, IRewardDistributor {
    // ========== CONSTANTS & IMMUTABLES ========== //

    /// @notice Role that can update merkle roots
    bytes32 public constant ROLE_MERKLE_UPDATER = "rewards_merkle_updater";

    /// @notice Minimum epoch duration
    uint40 public constant MIN_EPOCH_DURATION = 1 days;

    /// @notice Timestamp when first epoch begins (00:00:00 UTC)
    uint40 public immutable EPOCH_START_DATE;

    // ========== STATE VARIABLES ========== //

    /// @notice Mapping from epochEndDate => merkle root
    mapping(uint256 epochEndDate => bytes32 merkleRoot) public epochMerkleRoots;

    /// @notice Mapping from user address => epochEndDate => claimed status
    mapping(address user => mapping(uint256 epochEndDate => bool claimed)) public hasClaimed;

    /// @notice Last epoch end date for which a merkle root was set
    uint40 public lastEpochEndDate;

    // ========== MODIFIERS ========== //

    modifier onlyAuthorized(bytes32 role_) {
        ROLES.requireRole(role_, msg.sender);
        _;
    }

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructor
    ///
    /// @param  kernel_             The Kernel address
    /// @param  epochStartDate_     The timestamp when first epoch begins (00:00:00 UTC)
    constructor(address kernel_, uint256 epochStartDate_) Policy(Kernel(kernel_)) {
        if (epochStartDate_ == 0) revert RewardDistributor_EpochIsZero();
        _validateEpochStartOfDay(epochStartDate_);

        // Note: epochStartDate_ is truncated to uint40. Max uint40 is ~year 36812.
        EPOCH_START_DATE = uint40(epochStartDate_);
        // Initialize to 23:59:59 UTC of the day before EPOCH_START_DATE
        // This allows the first endEpoch call to use epochEndDate = EPOCH_START_DATE + 1 days - 1
        lastEpochEndDate = EPOCH_START_DATE - 1;
        // Disabled by default by PolicyEnabler
    }

    // ========== POLICY VERSION ========== //

    function VERSION() external pure virtual returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
        return (major, minor);
    }

    // ========== INTERNAL EPOCH MANAGEMENT ========== //

    /// @notice Sets a merkle root for an epoch.
    /// @dev The core internal function that validates and updates state.
    ///      Derived contracts call this from their public function at the end of an epoch,
    ///      then add token-specific logic and events afterward.
    ///
    /// @param epochEndDate_ The epoch end date (23:59:59 UTC timestamp).
    /// @param merkleRoot_ The Merkle root for the epoch's distribution.
    function _setMerkleRoot(uint40 epochEndDate_, bytes32 merkleRoot_) internal virtual {
        // Validate input
        if (merkleRoot_ == bytes32(0)) revert RewardDistributor_InvalidProof();

        // Ensure the epoch hasn't already been set
        if (epochMerkleRoots[epochEndDate_] != bytes32(0))
            revert RewardDistributor_EpochAlreadySet(epochEndDate_);

        // Validate epochEndDate is at 23:59:59 UTC (end of day)
        _validateEpochEndOfDay(epochEndDate_);

        // Validate epochEndDate is at least 1 day after lastEpochEndDate
        if (epochEndDate_ < lastEpochEndDate + MIN_EPOCH_DURATION) {
            revert RewardDistributor_EpochTooEarly();
        }

        // Set the merkle root for this epoch
        epochMerkleRoots[epochEndDate_] = merkleRoot_;

        // Update lastEpochEndDate
        lastEpochEndDate = epochEndDate_;

        emit MerkleRootSet(epochEndDate_, merkleRoot_);
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Validate that an epoch start date is at 00:00:00 UTC (midnight / start of day)
    ///
    /// @param  epochStartDate_ The epoch start date to validate
    function _validateEpochStartOfDay(uint256 epochStartDate_) internal pure {
        if (epochStartDate_ % 1 days != 0) revert RewardDistributor_InvalidEpochTimestamp();
    }

    /// @notice Validate that an epoch end date is at 23:59:59 UTC (end of day)
    ///
    /// @param  epochEndDate_ The epoch end date to validate
    function _validateEpochEndOfDay(uint256 epochEndDate_) internal pure {
        if ((epochEndDate_ + 1) % 1 days != 0) revert RewardDistributor_InvalidEpochTimestamp();
    }

    /// @notice Validate claim input arrays
    ///
    /// @param  epochEndDates_      Array of epoch end dates to claim
    /// @param  amounts_            Array of amounts for each epoch
    /// @param  proofs_             Array of Merkle proofs, one per epoch
    function _validateClaimArrays(
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) internal pure {
        if (epochEndDates_.length == 0) revert RewardDistributor_NoEpochsSpecified();
        if (epochEndDates_.length != amounts_.length || epochEndDates_.length != proofs_.length) {
            revert RewardDistributor_ArrayLengthMismatch();
        }
    }

    // ========== INTERNAL MERKLE PROOF HELPERS ========== //

    /// @notice Computes the leaf node for merkle verification.
    ///
    /// @param user_ The address of the user.
    /// @param epochEndDate_ The epoch end date.
    /// @param amount_ The amount.
    /// @return The computed leaf hash.
    function _computeLeaf(
        address user_,
        uint256 epochEndDate_,
        uint256 amount_
    ) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(user_, epochEndDate_, amount_))));
    }

    /// @notice Verify Merkle proof without modifying state
    ///
    /// @param  user_           The user address
    /// @param  epochEndDate_   The epoch end date
    /// @param  amount_         The amount to verify
    /// @param  proof_          The Merkle proof
    function _verifyProof(
        address user_,
        uint256 epochEndDate_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal view virtual {
        bytes32 leaf = _computeLeaf(user_, epochEndDate_, amount_);

        if (!MerkleProof.verify(proof_, epochMerkleRoots[epochEndDate_], leaf)) {
            revert RewardDistributor_InvalidProof();
        }
    }

    /// @notice Verify Merkle proof without reverting on failure
    ///
    /// @param  user_           The user address
    /// @param  epochEndDate_   The epoch end date
    /// @param  amount_         The amount to verify
    /// @param  proof_          The Merkle proof
    /// @return isValid         True if proof is valid and claimable, false otherwise
    function _verifyProofSafe(
        address user_,
        uint256 epochEndDate_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal view virtual returns (bool isValid) {
        // Check if already claimed
        if (hasClaimed[user_][epochEndDate_]) return false;

        bytes32 leaf = _computeLeaf(user_, epochEndDate_, amount_);

        return MerkleProof.verify(proof_, epochMerkleRoots[epochEndDate_], leaf);
    }

    /// @notice Checks if a claim is valid without modifying state.
    /// @dev Combines: merkle root exists + not claimed + valid proof.
    ///
    /// @param user_ The address of the user.
    /// @param epochEndDate_ The epoch end date.
    /// @param amount_ The amount to check.
    /// @param proof_ The Merkle proof.
    /// @return True if claim would succeed, false otherwise.
    function _isClaimable(
        address user_,
        uint256 epochEndDate_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal view virtual returns (bool) {
        if (epochMerkleRoots[epochEndDate_] == bytes32(0)) return false;
        return _verifyProofSafe(user_, epochEndDate_, amount_, proof_);
    }

    /// @notice Verify Merkle proof and mark epoch as claimed for user
    ///
    /// @param  user_           The user address
    /// @param  epochEndDate_   The epoch end date
    /// @param  amount_         The amount to verify
    /// @param  proof_          The Merkle proof
    function _verifyAndMarkClaimed(
        address user_,
        uint256 epochEndDate_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal virtual {
        // Verify proof first
        _verifyProof(user_, epochEndDate_, amount_, proof_);

        // Mark as claimed
        hasClaimed[user_][epochEndDate_] = true;
    }

    /// @notice Validates claim preconditions, verify proof, and mark as claimed.
    /// @dev Combines common validation logic:
    ///      1. Check not already claimed.
    ///      2. Check merkle root is set.
    ///      3. Verify proof and mark claimed.
    ///
    /// @param user_ The address of the user.
    /// @param epochEndDate_ The epoch end date.
    /// @param amount_ The amount to claim.
    /// @param proof_ The Merkle proof.
    function _validateAndMarkClaimed(
        address user_,
        uint256 epochEndDate_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal virtual {
        if (hasClaimed[user_][epochEndDate_])
            revert RewardDistributor_AlreadyClaimed(epochEndDate_);
        if (epochMerkleRoots[epochEndDate_] == bytes32(0))
            revert RewardDistributor_MerkleRootNotSet(epochEndDate_);

        _verifyAndMarkClaimed(user_, epochEndDate_, amount_, proof_);
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
