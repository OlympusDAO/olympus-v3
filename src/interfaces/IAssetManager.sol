// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

interface IAssetManager {
    // ========== ERRORS ========== //

    error AssetManager_NotConfigured();
    error AssetManager_VaultAlreadySet();
    error AssetManager_VaultAssetMismatch();

    // ========== EVENTS ========== //

    event AssetConfigured(address indexed asset, address indexed vault);
    event AssetDeposited(
        address indexed asset,
        address indexed depositor,
        address indexed operator,
        uint256 amount,
        uint256 shares
    );
    event AssetWithdrawn(
        address indexed asset,
        address indexed withdrawer,
        address indexed operator,
        uint256 amount,
        uint256 shares
    );

    /// @notice Get the number of shares deposited for an asset and operator
    ///
    /// @param  asset_      The asset to get the deposited shares for
    /// @param  operator_   The operator to get the deposited shares for
    /// @return shares      The number of shares deposited
    function getDepositedShares(
        address asset_,
        address operator_
    ) external view returns (uint256 shares);

    /// @notice Get the number of assets deposited for an asset and operator
    ///
    /// @param  asset_      The asset to get the deposited assets for
    /// @param  operator_   The operator to get the deposited assets for
    /// @return assets      The number of assets deposited
    function getDepositedAssets(
        address asset_,
        address operator_
    ) external view returns (uint256 assets);

    /// @notice Get the configuration for an asset
    ///
    /// @param  asset_      The asset to get the configuration for
    /// @return isConfigured  Whether the asset is approved
    /// @return vault       The vault to use
    function getAssetConfiguration(
        address asset_
    ) external view returns (bool isConfigured, address vault);
}
