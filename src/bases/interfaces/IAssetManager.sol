// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

/// @title  IAssetManager
/// @notice This interface defines the functions for custodying assets.
///         A depositor can deposit assets into a vault, and withdraw them later.
///         An operator is the contract that acts on behalf of the depositor. Only operators can interact with the contract. The deposits facilitated by an operator are siloed from other operators.
interface IAssetManager {
    // ========== ERRORS ========== //

    error AssetManager_NotConfigured();
    error AssetManager_InvalidAsset();
    error AssetManager_VaultAlreadySet();
    error AssetManager_VaultAssetMismatch();
    error AssetManager_ZeroAmount();

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

    /// @notice Get the number of assets deposited for an asset and operator
    ///
    /// @param  asset_          The asset to get the deposited shares for
    /// @param  operator_       The operator to get the deposited shares for
    /// @return shares          The number of shares deposited
    /// @return sharesInAssets  The number of shares deposited (in terms of assets)
    function getOperatorAssets(
        IERC20 asset_,
        address operator_
    ) external view returns (uint256 shares, uint256 sharesInAssets);

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
