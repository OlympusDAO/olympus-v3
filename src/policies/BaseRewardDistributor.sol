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

    /// @notice The TRSRY module
    TRSRYv1 internal TRSRY;

    /// @notice The reward token
    IERC20 public immutable REWARD_TOKEN;

    /// @notice The reward token vault
    IERC4626 public immutable REWARD_TOKEN_VAULT;

    /// @notice Mapping from epochStartDate => merkle root
    mapping(uint256 epochStartDate => bytes32 merkleRoot) public epochMerkleRoots;

    /// @notice Mapping from user address => epochStartDate => claimed status
    mapping(address user => mapping(uint256 epochStartDate => bool claimed)) public hasClaimed;

    /// @notice Last epoch start date for which a merkle root was set
    uint40 public lastEpochStartDate;

    /// @notice Timestamp when epoch 0 begins
    uint40 public immutable EPOCH_START_DATE;

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
    /// @param  epochStartDate_     The timestamp when epoch 0 begins (midnight UTC of start date)
    constructor(
        address kernel_,
        address rewardTokenVault_,
        uint256 epochStartDate_
    ) Policy(Kernel(kernel_)) {
        if (rewardTokenVault_ == address(0)) revert RewardDistributor_InvalidAddress();
        if (epochStartDate_ == 0) revert RewardDistributor_InvalidAddress();
        _validateEpochStartOfDay(epochStartDate_);
        REWARD_TOKEN = IERC20(IERC4626(rewardTokenVault_).asset());
        REWARD_TOKEN_VAULT = IERC4626(rewardTokenVault_);
        EPOCH_START_DATE = uint40(epochStartDate_);
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

    /// @notice Set the Merkle root for an epoch
    /// @dev    - Only callable by the ROLE_MERKLE_UPDATER role
    ///         - Epochs can be set in any order
    ///         - Epoch start date must be at least 1 day after the last epoch start date
    ///         - Epoch start date must be at the exact beginning of a day (midnight UTC)
    ///         - Merkle tree cannot be updated once set
    ///
    /// @param  epochStartDate_ The epoch start date (timestamp) being set
    /// @param  merkleRoot_     The Merkle root for the epoch's distribution
    /// @return epochStartDate  The epoch start date that was set
    function setMerkleRoot(
        uint40 epochStartDate_,
        bytes32 merkleRoot_
    )
        external
        virtual
        onlyAuthorized(ROLE_MERKLE_UPDATER)
        onlyEnabled
        returns (uint256 epochStartDate)
    {
        // Validate input
        if (merkleRoot_ == bytes32(0)) revert RewardDistributor_InvalidProof();

        // Ensure the epoch hasn't already been set
        if (epochMerkleRoots[epochStartDate_] != bytes32(0))
            revert RewardDistributor_EpochAlreadySet(epochStartDate_);

        // Validate epochStartDate is at the exact beginning of a day (midnight UTC)
        _validateEpochStartOfDay(epochStartDate_);

        // Validate epochStartDate is at least 1 day after lastEpochStartDate
        if (lastEpochStartDate != 0 && epochStartDate_ < lastEpochStartDate + 1 days) {
            revert RewardDistributor_EpochTooEarly();
        }

        // Set the merkle root for this epoch
        epochMerkleRoots[epochStartDate_] = merkleRoot_;

        // Update lastEpochStartDate
        lastEpochStartDate = epochStartDate_;

        epochStartDate = epochStartDate_;

        _emitMerkleRootSet(epochStartDate_, merkleRoot_);
    }

    // ========== CLAIM FUNCTIONS ========== //

    /// @notice Preview the claimable rewards for a user without claiming
    /// @dev    Returns 0 amounts if no valid claims are found (Merkle root not set or proof invalid)
    ///
    /// @param  user_                   The user address to preview claims for
    /// @param  claimEpochStartDates_   Array of epoch start dates to preview
    /// @param  amounts_                Array of amounts for each epoch (must match Merkle leaves)
    /// @param  proofs_                 Array of Merkle proofs, one per epoch
    /// @return claimableAmount         The total amount of reward token claimable
    /// @return vaultShares             The amount of vault shares equivalent to the claimable amount
    function previewClaim(
        address user_,
        uint256[] calldata claimEpochStartDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external view returns (uint256 claimableAmount, uint256 vaultShares) {
        // Validate array lengths, return 0 if invalid
        if (
            claimEpochStartDates_.length == 0 ||
            claimEpochStartDates_.length != amounts_.length ||
            claimEpochStartDates_.length != proofs_.length
        ) {
            return (0, 0);
        }

        for (uint256 i = 0; i < claimEpochStartDates_.length; ) {
            uint256 epochStartDate = claimEpochStartDates_[i];
            uint256 amount = amounts_[i];

            // Skip epochs without merkle roots set
            if (epochMerkleRoots[epochStartDate] != bytes32(0)) {
                // Verify proof safely, skip if invalid or already claimed
                if (_verifyProofSafe(user_, epochStartDate, amount, proofs_[i])) {
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

    /// @notice Claim rewards for one or more epochs in a single transaction
    ///
    /// @param  epochStartDates_    Array of epoch start dates to claim
    /// @param  amounts_            Array of amounts for each epoch (must match Merkle leaves)
    /// @param  proofs_             Array of Merkle proofs, one per epoch
    /// @param  asVaultToken_       If true, claim as vault token; if false, unwrap to underlying token
    function claim(
        uint256[] calldata epochStartDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_,
        bool asVaultToken_
    ) external virtual onlyEnabled {
        _validateClaimArrays(epochStartDates_, amounts_, proofs_);

        uint256 totalAmount = _processClaims(msg.sender, epochStartDates_, amounts_, proofs_);

        _transferRewards(msg.sender, totalAmount, epochStartDates_.length, asVaultToken_);
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Validate that an epoch start date is at the exact beginning of a day (midnight UTC)
    ///
    /// @param  epochStartDate_ The epoch start date to validate
    function _validateEpochStartOfDay(uint256 epochStartDate_) internal pure {
        if (epochStartDate_ % 1 days != 0) revert RewardDistributor_EpochNotStartOfDay();
    }

    /// @notice Validate claim input arrays
    ///
    /// @param  epochStartDates_    Array of epoch start dates to claim
    /// @param  amounts_            Array of amounts for each epoch
    /// @param  proofs_             Array of Merkle proofs, one per epoch
    function _validateClaimArrays(
        uint256[] calldata epochStartDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) internal pure {
        if (epochStartDates_.length == 0) revert RewardDistributor_NoEpochsSpecified();
        if (
            epochStartDates_.length != amounts_.length || epochStartDates_.length != proofs_.length
        ) {
            revert RewardDistributor_ArrayLengthMismatch();
        }
    }

    /// @notice Process claims and return total amount
    ///
    /// @param  user_               The user address claiming rewards
    /// @param  epochStartDates_    Array of epoch start dates to claim
    /// @param  amounts_            Array of amounts for each epoch
    /// @param  proofs_             Array of Merkle proofs, one per epoch
    /// @return totalAmount         The total amount claimed across all epochs
    function _processClaims(
        address user_,
        uint256[] calldata epochStartDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) internal returns (uint256 totalAmount) {
        for (uint256 i = 0; i < epochStartDates_.length; ) {
            uint256 epochStartDate = epochStartDates_[i];
            uint256 amount = amounts_[i];

            // Skip if already claimed
            if (hasClaimed[user_][epochStartDate]) {
                unchecked {
                    ++i;
                }
                continue;
            }

            // Verify merkle root is set for this epoch
            if (epochMerkleRoots[epochStartDate] == bytes32(0))
                revert RewardDistributor_MerkleRootNotSet(epochStartDate);

            // Verify and mark as claimed
            _verifyAndMarkClaimed(user_, epochStartDate, amount, proofs_[i]);

            totalAmount += amount;

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Verify Merkle proof without modifying state
    ///
    /// @param  user_           The user address
    /// @param  epochStartDate_ The epoch start date
    /// @param  amount_         The amount to verify
    /// @param  proof_          The Merkle proof
    function _verifyProof(
        address user_,
        uint256 epochStartDate_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal view virtual {
        // Construct the leaf node: keccak256(abi.encode(user, epochStartDate, amount))
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(user_, epochStartDate_, amount_)))
        );

        // Verify Merkle proof
        if (!MerkleProof.verify(proof_, epochMerkleRoots[epochStartDate_], leaf)) {
            revert RewardDistributor_InvalidProof();
        }
    }

    /// @notice Verify Merkle proof without reverting on failure
    ///
    /// @param  user_           The user address
    /// @param  epochStartDate_ The epoch start date
    /// @param  amount_         The amount to verify
    /// @param  proof_          The Merkle proof
    /// @return isValid         True if proof is valid and claimable, false otherwise
    function _verifyProofSafe(
        address user_,
        uint256 epochStartDate_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal view virtual returns (bool isValid) {
        // Check if already claimed
        if (hasClaimed[user_][epochStartDate_]) return false;

        // Construct the leaf node: keccak256(abi.encode(user, epochStartDate, amount))
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(user_, epochStartDate_, amount_)))
        );

        // Verify Merkle proof and return result
        return MerkleProof.verify(proof_, epochMerkleRoots[epochStartDate_], leaf);
    }

    /// @notice Verify Merkle proof and mark epoch as claimed for user
    ///
    /// @param  user_           The user address
    /// @param  epochStartDate_ The epoch start date
    /// @param  amount_         The amount to verify
    /// @param  proof_          The Merkle proof
    function _verifyAndMarkClaimed(
        address user_,
        uint256 epochStartDate_,
        uint256 amount_,
        bytes32[] calldata proof_
    ) internal virtual {
        // Verify proof first
        _verifyProof(user_, epochStartDate_, amount_, proof_);

        // Mark as claimed
        hasClaimed[user_][epochStartDate_] = true;
    }

    /// @notice Internal function to transfer rewards from treasury
    /// @dev    Must be implemented by derived contracts
    ///
    /// @param  to_             Address to transfer rewards to
    /// @param  amount_         Amount to transfer
    /// @param  epochCount_     Number of epochs being claimed (for event)
    /// @param  asVaultToken_   If true, transfer as vault token; if false, unwrap first
    function _transferRewards(
        address to_,
        uint256 amount_,
        uint256 epochCount_,
        bool asVaultToken_
    ) internal virtual;

    /// @notice Emit Merkle root set event
    ///
    /// @param  epochStartDate_ The epoch start date
    /// @param  merkleRoot_     The Merkle root
    function _emitMerkleRootSet(uint256 epochStartDate_, bytes32 merkleRoot_) internal {
        emit MerkleRootSet(epochStartDate_, merkleRoot_, address(REWARD_TOKEN));
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
