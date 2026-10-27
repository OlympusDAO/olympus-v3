// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IERC4626} from "@openzeppelin-5.3.0/interfaces/IERC4626.sol";
import {IERC7540Redeem} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7540.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";

/// @title YieldRepurchaseFacilityV2VaultLib
/// @notice An internal library that values the shares of a registered vault of the
///         YieldRepurchaseFacilityV2 by the redemption class of the vault.
/// @dev The functions are internal and take values, so they are compiled into the
///      facility, into its linked libraries, and into the lens.
///
///      A vault with synchronous redemption is valued through its previews, which report
///      the executable amounts. A vault with asynchronous redemption (ERC7540) reverts
///      on `previewRedeem` and `previewWithdraw`, so an asset flagged `asyncRedeem` is
///      valued through `convertToAssets` and `convertToShares`. The redemption payout of
///      such a vault is not bound to `convertToAssets`, so the valuation of such an
///      asset is an estimate.
library YieldRepurchaseFacilityV2VaultLib {
    /// @notice Returns whether the vault advertises asynchronous redemption
    ///         (`IERC7540Redeem`) through ERC165.
    /// @dev A vault that does not implement ERC165 is reported as synchronous.
    /// @param vault_ The vault to query.
    /// @return Whether the vault advertises asynchronous redemption.
    function isAsyncRedeem(address vault_) internal view returns (bool) {
        return ERC165Checker.supportsInterface(vault_, type(IERC7540Redeem).interfaceId);
    }

    /// @notice Returns the reserve value of `shares_` of the vault, rounded down.
    /// @dev `previewRedeem` for a synchronous asset, `convertToAssets` for an asset flagged
    ///      `asyncRedeem`.
    /// @param vault_ The vault.
    /// @param asyncRedeem_ Whether the asset is flagged `asyncRedeem`.
    /// @param shares_ The share amount to value.
    /// @return The value, in reserve units.
    function sharesToAssets(
        address vault_,
        bool asyncRedeem_,
        uint256 shares_
    ) internal view returns (uint256) {
        IERC4626 vault = IERC4626(vault_);
        return asyncRedeem_ ? vault.convertToAssets(shares_) : vault.previewRedeem(shares_);
    }

    /// @notice Returns the share amount that covers `assets_` of the reserve, rounded up.
    /// @dev `previewWithdraw` for a synchronous asset, which the vault rounds up. For an
    ///      asset flagged `asyncRedeem` the amount is `convertToShares`, which the vault
    ///      rounds down, raised by one share when the floored amount converts back to
    ///      less than `assets_`. A vault whose `convertToShares` and `convertToAssets`
    ///      are not linear in the amount, or report an averaged rate, can value the
    ///      raised amount below `assets_` as well; the callers then measure the covered
    ///      value through `sharesToAssets`.
    /// @param vault_ The vault.
    /// @param asyncRedeem_ Whether the asset is flagged `asyncRedeem`.
    /// @param assets_ The reserve amount to cover.
    /// @return shares The share amount.
    function assetsToShares(
        address vault_,
        bool asyncRedeem_,
        uint256 assets_
    ) internal view returns (uint256 shares) {
        IERC4626 vault = IERC4626(vault_);
        if (!asyncRedeem_) return vault.previewWithdraw(assets_);

        shares = vault.convertToShares(assets_);
        if (vault.convertToAssets(shares) < assets_) ++shares;
    }

    /// @notice Returns the vault's conversion rate: the reserve value of one whole
    ///         share, rounded down.
    /// @dev The probe amount `10 ** reserveDecimals_` is one whole share because
    ///      `addAsset` requires the share token decimals to equal the reserve decimals.
    ///      The rate is `sharesToAssets` of that amount.
    /// @param vault_ The vault.
    /// @param asyncRedeem_ Whether the asset is flagged `asyncRedeem`.
    /// @param reserveDecimals_ The reserve decimals, equal to the share decimals.
    /// @return The conversion rate, in reserve units per whole share.
    function conversionRate(
        address vault_,
        bool asyncRedeem_,
        uint8 reserveDecimals_
    ) internal view returns (uint256) {
        return
            sharesToAssets(
                vault_,
                asyncRedeem_,
                YieldRepurchaseFacilityV2Constants.DECIMAL_BASE ** reserveDecimals_
            );
    }
}
