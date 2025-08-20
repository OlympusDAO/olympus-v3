// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";

/// @title  IAssetManager
/// @notice This interface defines the functions for custodying assets.
///         A depositor can deposit assets into a vault, and withdraw them later.
///         An operator is the contract that acts on behalf of the depositor. Only operators can interact with the contract. The deposits facilitated by an operator are siloed from other operators.
interface IAssetManager {
    // ========== ERRORS ========== //

    error AssetManager_NotConfigured();

    error AssetManager_InvalidAsset();

    error AssetManager_AssetAlreadyConfigured();

    error AssetManager_VaultAssetMismatch();

    error AssetManager_ZeroAmount();

    error AssetManager_DepositCapExceeded(
        address asset,
        uint256 existingDepositAmount,
        uint256 depositCap
    );

    error AssetManager_MinimumDepositNotMet(
        address asset,
        uint256 depositAmount,
        uint256 minimumDeposit
    );

    error AssetManager_MinimumDepositExceedsDepositCap(
        address asset,
        uint256 minimumDeposit,
        uint256 depositCap
    );

    // ========== EVENTS ========== //

    event AssetConfigured(address indexed asset, address indexed vault);

    /// @notice Emitted when an asset's deposit cap is updated
    /// @param asset      The ERC20 asset
    /// @param depositCap The new deposit cap amount (in asset units)
    event AssetDepositCapSet(address indexed asset, uint256 depositCap);

    /// @notice Emitted when an asset's minimum single-deposit amount is updated
    /// @param asset           The ERC20 asset
    /// @param minimumDeposit  The new minimum deposit amount (in asset units)
    event AssetMinimumDepositSet(address indexed asset, uint256 minimumDeposit);

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

    /// @notice Configuration for an asset
    ///
    /// @param isConfigured   Whether the asset is configured
    /// @param depositCap     The maximum amount of assets that can be deposited. Set to 0 to disable deposits.
    /// @param minimumDeposit The minimum amount of assets that can be deposited in a single transaction (set to 0 to disable the check)
    /// @param vault          The ERC4626 vault that the asset is deposited into
    struct AssetConfiguration {
        bool isConfigured;
        uint256 depositCap;
        uint256 minimumDeposit;
        address vault;
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
