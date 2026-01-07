// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

// Base Contract
import {BaseRewardDistributor} from "./BaseRewardDistributor.sol";

// Interfaces
import {IVaultRewardDistributor} from "src/policies/interfaces/IVaultRewardDistributor.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";

// Bophades
import {Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

/// @title  Base Vault Reward Distributor
/// @notice Abstract base contract for Merkle tree-based reward distribution with a ERC4626 vault.
/// @dev This base extends `BaseRewardDistributor` with vault token support:
///      - Rewards are held in treasury as vault tokens (e.g., sUSDS).
///      - Users can claim as vault token or unwrap to underlying.
///      - Derived contracts implement _transferRewards for specific transfer logic.
///
///      Architecture:
///      - Rewards are calculated off-chain.
///      - Backend generates Merkle trees with accumulated rewards per user.
///      - Merkle roots are posted on-chain by authorized role.
///      - Users submit proofs to claim their rewards.
abstract contract BaseVaultRewardDistributor is BaseRewardDistributor, IVaultRewardDistributor {
    // ========== IMMUTABLES ========== //

    /// @notice The reward token (the underlying asset of the vault)
    IERC20 public immutable REWARD_TOKEN;

    /// @notice The reward token ERC4626 vault
    IERC4626 public immutable REWARD_TOKEN_VAULT;

    // ========== STATE VARIABLES ========== //

    /// @notice The TRSRY module
    TRSRYv1 internal TRSRY;

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
    ) BaseRewardDistributor(kernel_, epochStartDate_) {
        if (rewardTokenVault_ == address(0)) revert RewardDistributor_InvalidAddress();
        REWARD_TOKEN = IERC20(IERC4626(rewardTokenVault_).asset());
        REWARD_TOKEN_VAULT = IERC4626(rewardTokenVault_);
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

    // ========== ADMIN FUNCTIONS FOR MERKLE ROOT MANAGEMENT ========== //

    /// @inheritdoc IVaultRewardDistributor
    function endEpoch(
        uint40 epochEndDate_,
        bytes32 merkleRoot_
    ) external virtual onlyAuthorized(ROLE_MERKLE_UPDATER) onlyEnabled {
        // Set merkle root (validates and emits MerkleRootSet)
        _setMerkleRoot(epochEndDate_, merkleRoot_);

        // Emit vault-specific event
        emit EpochEnded(epochEndDate_, address(REWARD_TOKEN));
    }

    // ========== CLAIM FUNCTIONS ========== //

    /// @inheritdoc IVaultRewardDistributor
    function previewClaim(
        address user_,
        uint256[] calldata epochEndDates_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external view returns (uint256 claimableAmount, uint256 vaultShares) {
        // Validate array lengths, return 0 if invalid
        uint256 len = epochEndDates_.length;
        if (len == 0 || len != amounts_.length || len != proofs_.length) {
            return (0, 0);
        }

        for (uint256 i = 0; i < len; ++i) {
            // Skip epochs without merkle roots set.
            if (_isClaimable(user_, epochEndDates_[i], amounts_[i], proofs_[i])) {
                claimableAmount += amounts_[i];
            }
        }

        // Calculate equivalent vault shares
        if (claimableAmount > 0) {
            vaultShares = REWARD_TOKEN_VAULT.previewWithdraw(claimableAmount);
        }
    }

    /// @inheritdoc IVaultRewardDistributor
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

        for (uint256 i = 0; i < epochEndDates_.length; ++i) {
            uint256 epochEndDate = epochEndDates_[i];
            uint256 amount = amounts_[i];

            // Validate preconditions, verify proof, and mark as claimed
            _validateAndMarkClaimed(user_, epochEndDate, amount, proofs_[i]);

            totalAmount += amount;
            tempClaimedDates[claimedCount] = epochEndDate;
            unchecked {
                ++claimedCount;
            }
        }

        claimedEpochEndDates = new uint256[](claimedCount);
        for (uint256 i = 0; i < claimedCount; ++i) {
            claimedEpochEndDates[i] = tempClaimedDates[i];
        }
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

    // ========== ERC165 ========== //

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(BaseRewardDistributor, IERC165) returns (bool) {
        return
            interfaceId == type(IVaultRewardDistributor).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
