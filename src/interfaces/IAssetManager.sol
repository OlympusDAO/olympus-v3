// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

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

    // ========== DATA STRUCTURES ========== //

    struct AssetConfiguration {
        bool isConfigured;
        IERC4626 vault;
    }

    // ========== ASSET FUNCTIONS ========== //

    /// @notice Get the number of shares deposited for an asset and operator
    ///
    /// @param  asset_      The asset to get the deposited shares for
    /// @param  operator_   The operator to get the deposited shares for
    /// @return shares      The number of shares deposited
    function getDepositedShares(
        IERC20 asset_,
        address operator_
    ) external view returns (uint256 shares);

    /// @notice Get the number of assets deposited for an asset and operator
    ///
    /// @param  asset_      The asset to get the deposited assets for
    /// @param  operator_   The operator to get the deposited assets for
    /// @return assets      The number of assets deposited
    function getDepositedAssets(
        IERC20 asset_,
        address operator_
    ) external view returns (uint256 assets);

    /// @notice Get the configuration for an asset
    ///
    /// @param  asset_          The asset to get the configuration for
    /// @return configuration   The configuration for the asset
    function getAssetConfiguration(
        IERC20 asset_
    ) external view returns (AssetConfiguration memory configuration);

    /// @notice Get the assets that are configured
    ///
    /// @return assets  The assets that are configured
    function getConfiguredAssets() external view returns (IERC20[] memory assets);
}
