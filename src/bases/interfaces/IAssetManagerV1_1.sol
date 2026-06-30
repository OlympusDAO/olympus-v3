// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";

/// @title IAssetManagerV1_1
/// @notice Extends IAssetManager with the redeem-shares configuration: an asset whose
///         withdrawals deliver the configured vault's shares (for example sUSDe)
///         rather than redeeming them to the underlying asset.
/// @dev The redeem-shares flag defaults to false, the original behaviour: a withdrawal redeems
///      the vault shares to the asset.
interface IAssetManagerV1_1 is IAssetManager {
    // ========== ERRORS ========== //

    /// @notice Thrown when configuring an asset with redeem-shares enabled but no vault, since
    ///         there are no vault shares to deliver.
    error AssetManager_RedeemSharesRequiresVault();

    // ========== EVENTS ========== //

    /// @notice Emitted when an asset's redeem-shares flag is configured.
    /// @param asset The ERC20 asset.
    /// @param redeemShares Whether withdrawals deliver the vault's shares instead of the asset.
    event AssetRedeemSharesSet(address indexed asset, bool redeemShares);

    // ========== VIEWS ========== //

    /// @notice Whether withdrawals of `asset_` deliver the configured vault's shares directly
    ///         instead of redeeming them to the asset.
    /// @param asset_ The asset to query.
    /// @return redeemShares True if withdrawals deliver vault shares, false to redeem to the asset.
    function getRedeemShares(IERC20 asset_) external view returns (bool redeemShares);
}
