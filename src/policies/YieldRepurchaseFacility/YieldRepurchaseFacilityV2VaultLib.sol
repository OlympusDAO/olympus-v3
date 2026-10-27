// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IERC4626} from "@openzeppelin-5.3.0/interfaces/IERC4626.sol";
import {IERC7540Redeem} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7540.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";

/// @title YieldRepurchaseFacilityV2VaultLib
/// @notice An internal library that values the shares of a registered vault of the
///         YieldRepurchaseFacilityV2 by the redemption class of the vault.
/// @dev The functions are internal: they are compiled into the facility and into
///      `YieldRepurchaseFacilityV2AssetRegistryLib`, and read the configuration storage of
///      the facility.
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
    /// @param config_ The vault's configuration storage.
    /// @param shares_ The share amount to value.
    /// @return The value, in reserve units.
    function sharesToAssets(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        uint256 shares_
    ) internal view returns (uint256) {
        IERC4626 vault = IERC4626(config_.vault);
        return config_.asyncRedeem ? vault.convertToAssets(shares_) : vault.previewRedeem(shares_);
    }

    /// @notice Returns the share amount that covers `assets_` of the reserve, rounded up.
    /// @dev `previewWithdraw` for a synchronous asset, which the vault rounds up. For an
    ///      asset flagged `asyncRedeem` the amount is `convertToShares`, which the vault
    ///      rounds down, raised by one share when the floored amount converts back to
    ///      less than `assets_`. A vault whose `convertToShares` and `convertToAssets`
    ///      are not linear in the amount, or report an averaged rate, can value the
    ///      raised amount below `assets_` as well; the callers then measure the covered
    ///      value through `sharesToAssets`.
    /// @param config_ The vault's configuration storage.
    /// @param assets_ The reserve amount to cover.
    /// @return shares The share amount.
    function assetsToShares(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        uint256 assets_
    ) internal view returns (uint256 shares) {
        IERC4626 vault = IERC4626(config_.vault);
        if (!config_.asyncRedeem) return vault.previewWithdraw(assets_);

        shares = vault.convertToShares(assets_);
        if (vault.convertToAssets(shares) < assets_) ++shares;
    }
}
