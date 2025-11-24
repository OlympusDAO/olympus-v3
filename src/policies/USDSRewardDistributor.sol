// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Base Contract
import {BaseRewardDistributor} from "./BaseRewardDistributor.sol";

// Interfaces
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

// Libraries
import {TransferHelper} from "src/libraries/TransferHelper.sol";

/// @title  USDS Reward Distributor
/// @notice Merkle tree-based rewards distribution for USDS rewards
/// @dev    This contract allows users to accumulate rewards based on their protocol activity
///         and claim rewards from a weekly Merkle tree distribution.
///
///         Extends BaseRewardDistributor with USDS/sUSDS-specific functionality.
contract USDSRewardDistributor is BaseRewardDistributor {
    using TransferHelper for ERC20;

    // ========== STATE VARIABLES ========== //

    /// @notice The USDS reward token
    IERC20 public immutable REWARD_TOKEN;

    /// @notice The sUSDS vault token
    IERC4626 public immutable REWARD_TOKEN_VAULT;

    // ========== CONSTRUCTOR ========== //

    /// @param kernel_              The Kernel address
    /// @param rewardTokenVault_    The ERC4626 vault token
    /// @param startTimestamp_      The timestamp when week 0 begins (typically midnight UTC of start date)
    constructor(
        address kernel_,
        address rewardTokenVault_,
        uint256 startTimestamp_
    ) BaseRewardDistributor(kernel_, startTimestamp_) {
        if (rewardTokenVault_ == address(0)) revert DRD_InvalidAddress();
        REWARD_TOKEN = IERC20(IERC4626(rewardTokenVault_).asset());
        REWARD_TOKEN_VAULT = IERC4626(rewardTokenVault_);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Preview the claimable rewards for a user without claiming
    /// @dev    This function does not modify state and allows users to verify their claims before submitting.
    ///         Returns 0 amounts if no valid claims are found (merkle root not set or proof invalid).
    ///
    /// @param  user_           The user address to preview claims for
    /// @param  claimWeeks_     Array of week numbers to preview
    /// @param  amounts_        Array of amounts for each week (must match merkle leaves)
    /// @param  proofs_         Array of merkle proofs, one per week
    /// @return claimableAmount The total amount of USDS claimable
    /// @return vaultShares     The amount of sUSDS vault shares equivalent to the claimable amount
    function previewClaim(
        address user_,
        uint256[] calldata claimWeeks_,
        uint256[] calldata amounts_,
        bytes32[][] calldata proofs_
    ) external view returns (uint256 claimableAmount, uint256 vaultShares) {
        // Validate array lengths, return 0 if invalid
        if (claimWeeks_.length == 0 || claimWeeks_.length != amounts_.length || claimWeeks_.length != proofs_.length) {
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

    // ========== INTERNAL OVERRIDES ========== //

    /// @inheritdoc BaseRewardDistributor
    /// @dev    Pulls sUSDS from the treasury, optionally unwraps it to USDS, and transfers to the user.
    function _transferRewards(
        address to_,
        uint256 amount_,
        uint256 weekCount_,
        bool asVaultToken_
    ) internal override {
        // Early return if no amount to transfer
        if (amount_ == 0) return;

        IERC4626 vault = IERC4626(address(REWARD_TOKEN_VAULT));

        if (asVaultToken_) {
            // Calculate how many vault shares represent the USDS amount
            uint256 vaultShares = vault.previewWithdraw(amount_);

            // Withdraw sUSDS from treasury and transfer directly to user
            TRSRY.withdrawReserves(address(this), ERC20(address(REWARD_TOKEN_VAULT)), vaultShares);
            ERC20(address(REWARD_TOKEN_VAULT)).safeTransfer(to_, vaultShares);

            // Emit vault token claimed event
            emit RewardsClaimedViaVault(to_, amount_, vaultShares, address(REWARD_TOKEN_VAULT), weekCount_);
        } else {
            // Calculate how much vault shares is needed to withdraw the exact USDS amount
            uint256 sharesNeeded = vault.previewWithdraw(amount_);

            // Withdraw sUSDS from treasury
            TRSRY.withdrawReserves(address(this), ERC20(address(REWARD_TOKEN_VAULT)), sharesNeeded);

            // Withdraw USDS from the vault and transfer to user
            uint256 sharesBurned = vault.withdraw(amount_, to_, address(this));

            // Calculate leftover sUSDS shares (if any due to rounding)
            uint256 leftoverShares = sharesNeeded - sharesBurned;

            // Return any leftover sUSDS to the treasury
            if (leftoverShares > 0) {
                ERC20(address(REWARD_TOKEN_VAULT)).safeTransfer(
                    address(TRSRY),
                    leftoverShares
                );
            }

            // Emit rewards claimed event with week count
            emit RewardsClaimed(to_, amount_, address(REWARD_TOKEN), weekCount_);
        }
    }

    /// @inheritdoc BaseRewardDistributor
    function _emitMerkleRootSet(uint256 week_, bytes32 merkleRoot_) internal override {
        emit MerkleRootSet(week_, merkleRoot_, address(REWARD_TOKEN));
    }
}
