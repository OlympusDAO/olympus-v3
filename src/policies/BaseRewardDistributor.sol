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
///         - Backend generates Merkle trees with accumulated rewards per user
///         - Merkle roots are posted on-chain by authorized role
///         - Users submit proofs to claim their rewards
abstract contract BaseRewardDistributor is Policy, PolicyEnabler, IRewardDistributor {
    // ========== STATE VARIABLES ========== //

    /// @notice Role that can update merkle roots
    bytes32 public constant ROLE_MERKLE_UPDATER = "rewards_merkle_updater";

    /// @notice Minimum epoch duration
    uint40 public constant MIN_EPOCH_DURATION = 1 days;

    /// @notice The TRSRY module
    TRSRYv1 internal TRSRY;

    /// @notice The reward token
    IERC20 public immutable REWARD_TOKEN;

    /// @notice The reward token vault
    IERC4626 public immutable REWARD_TOKEN_VAULT;

    /// @notice Timestamp when first epoch begins (00:00:00 UTC)
    uint40 public immutable EPOCH_START_DATE;

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
    /// @param  rewardTokenVault_   The ERC4626 vault token
    /// @param  epochStartDate_     The timestamp when first epoch begins (00:00:00 UTC)
    constructor(
        address kernel_,
        address rewardTokenVault_,
        uint256 epochStartDate_
    ) Policy(Kernel(kernel_)) {
        if (rewardTokenVault_ == address(0)) revert RewardDistributor_InvalidAddress();
        if (epochStartDate_ == 0) revert RewardDistributor_EpochIsZero();
        _validateEpochStartOfDay(epochStartDate_);
        REWARD_TOKEN = IERC20(IERC4626(rewardTokenVault_).asset());
        REWARD_TOKEN_VAULT = IERC4626(rewardTokenVault_);
        // Note: epochStartDate_ is truncated to uint40. Max uint40 is ~year 36812.
        EPOCH_START_DATE = uint40(epochStartDate_);
        // Initialize to 23:59:59 UTC of the day before EPOCH_START_DATE
        // This allows the first endEpoch call to use epochEndDate = EPOCH_START_DATE + 1 days - 1
        lastEpochEndDate = EPOCH_START_DATE - 1;
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
        permissions[0] = Permissions({
            keycode: trsryKeycode,
            funcSelector: TRSRY.withdrawReserves.selector
        });
    }

    function VERSION() external pure virtual returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
        return (major, minor);
    }

    // ========== MERKLE ROOT MANAGEMENT ========== //

    /// @notice Ends an epoch and sets its Merkle root
    /// @dev    - Only callable by the ROLE_MERKLE_UPDATER role
    ///         - Epoch end date must be at least 1 day after the last epoch end date
    ///         - Epoch end date must be at 23:59:59 UTC (end of day)
    ///         - Merkle tree cannot be updated once set
    ///
    /// @param  epochEndDate_   The epoch end date (23:59:59 UTC timestamp)
    /// @param  merkleRoot_     The Merkle root for the epoch's distribution
    function endEpoch(
        uint40 epochEndDate_,
        bytes32 merkleRoot_
    ) external virtual onlyAuthorized(ROLE_MERKLE_UPDATER) onlyEnabled {
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

        _emitMerkleRootSet(epochEndDate_, merkleRoot_);
    }

    // ========== CLAIM FUNCTIONS ========== //

    /// @notice Preview the claimable rewards for a user without claiming
    /// @dev    Returns 0 amounts if no valid claims are found (Merkle root not set or proof invalid)
    ///
    /// @param  user_               The user address to preview claims for
    /// @param  epochEndDates_      Array of epoch end dates to preview
    /// @param  amounts_            Array of amounts for each epoch (must match Merkle leaves)
    /// @param  proofs_             Array of Merkle proofs, one per epoch
    /// @return claimableAmount     The total amount of reward token claimable
    /// @return vaultShares         The amount of vault shares equivalent to the claimable amount
    function previewClaim(
        address user_,
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external view returns (uint256 claimableAmount, uint256 vaultShares) {
        // Validate array lengths, return 0 if invalid
        if (
            epochEndDates_.length == 0 ||
            epochEndDates_.length != amounts_.length ||
            epochEndDates_.length != proofs_.length
        ) {
            return (0, 0);
        }

        for (uint256 i = 0; i < epochEndDates_.length; ) {
            uint256 epochEndDate = epochEndDates_[i];
            uint256 amount = amounts_[i];

            // Skip epochs without merkle roots set
            if (epochMerkleRoots[epochEndDate] != bytes32(0)) {
                // Verify proof safely, skip if invalid or already claimed
                if (_verifyProofSafe(user_, epochEndDate, amount, proofs_[i])) {
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
    /// @param  epochEndDates_      Array of epoch end dates to claim
    /// @param  amounts_            Array of amounts for each epoch (must match Merkle leaves)
    /// @param  proofs_             Array of Merkle proofs, one per epoch
    /// @param  asVaultToken_       If true, claim as vault token; if false, unwrap to underlying token
    /// @return rewardToken         The address of the token transferred (vault token if `asVaultToken_`, otherwise underlying)
    /// @return tokensTransferred   The amount of tokens transferred (vault shares if `asVaultToken_`, otherwise underlying)
    function claim(
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_,
        bool asVaultToken_
    ) external virtual onlyEnabled returns (address rewardToken, uint256 tokensTransferred) {
        _validateClaimArrays(epochEndDates_, amounts_, proofs_);

        (uint256 totalAmount, uint256[] memory claimedEpochEndDates) = _processClaims(
            msg.sender,
            epochEndDates_,
            amounts_,
            proofs_
        );

        if (totalAmount == 0) revert RewardDistributor_NothingToClaim();

        (rewardToken, tokensTransferred) = _transferRewards(
            msg.sender,
            totalAmount,
            claimedEpochEndDates,
            asVaultToken_
        );
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

    /// @notice Process claims and return total amount and claimed epoch end dates
    ///
    /// @param  user_               The user address claiming rewards
    /// @param  epochEndDates_      Array of epoch end dates to claim
    /// @param  amounts_            Array of amounts for each epoch
    /// @param  proofs_             Array of Merkle proofs, one per epoch
    /// @return totalAmount         The total amount claimed across all epochs
    /// @return claimedEpochEndDates Array of epoch end dates that were actually claimed
    function _processClaims(
        address user_,
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) internal returns (uint256 totalAmount, uint256[] memory claimedEpochEndDates) {
        // Allocate max possible size, will trim later
        uint256[] memory tempClaimedDates = new uint256[](epochEndDates_.length);
        uint256 claimedCount = 0;

        for (uint256 i = 0; i < epochEndDates_.length; ) {
            uint256 epochEndDate = epochEndDates_[i];
            uint256 amount = amounts_[i];

            // Revert if already claimed
            if (hasClaimed[user_][epochEndDate]) {
                revert RewardDistributor_AlreadyClaimed(epochEndDate);
            }

            // Verify merkle root is set for this epoch
            if (epochMerkleRoots[epochEndDate] == bytes32(0))
                revert RewardDistributor_MerkleRootNotSet(epochEndDate);

            // Verify and mark as claimed
            _verifyAndMarkClaimed(user_, epochEndDate, amount, proofs_[i]);

            totalAmount += amount;
            tempClaimedDates[claimedCount] = epochEndDate;
            unchecked {
                ++claimedCount;
                ++i;
            }
        }

        claimedEpochEndDates = new uint256[](claimedCount);
        for (uint256 j = 0; j < claimedCount; ) {
            claimedEpochEndDates[j] = tempClaimedDates[j];
            unchecked {
                ++j;
            }
        }
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
        // Construct the leaf node: keccak256(abi.encode(user, epochEndDate, amount))
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(user_, epochEndDate_, amount_)))
        );

        // Verify Merkle proof
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

        // Construct the leaf node: keccak256(abi.encode(user, epochEndDate, amount))
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(user_, epochEndDate_, amount_)))
        );

        // Verify Merkle proof and return result
        return MerkleProof.verify(proof_, epochMerkleRoots[epochEndDate_], leaf);
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

    /// @notice Internal function to transfer rewards from treasury
    /// @dev    Must be implemented by derived contracts
    ///
    /// @param  to_             Address to transfer rewards to
    /// @param  amount_         Amount to transfer
    /// @param  epochEndDates_  Array of epoch end dates that were claimed (for event)
    /// @param  asVaultToken_   If true, transfer as vault token; if false, unwrap first
    /// @return rewardToken     The address of the token transferred (vault token if `asVaultToken_`, otherwise underlying)
    /// @return tokensTransferred The amount of tokens transferred (vault shares if `asVaultToken_`, otherwise underlying)
    function _transferRewards(
        address to_,
        uint256 amount_,
        uint256[] memory epochEndDates_,
        bool asVaultToken_
    ) internal virtual returns (address rewardToken, uint256 tokensTransferred);

    /// @notice Emit Merkle root set event
    ///
    /// @param  epochEndDate_   The epoch end date
    /// @param  merkleRoot_     The Merkle root
    function _emitMerkleRootSet(uint256 epochEndDate_, bytes32 merkleRoot_) internal {
        emit MerkleRootSet(epochEndDate_, merkleRoot_, address(REWARD_TOKEN));
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
