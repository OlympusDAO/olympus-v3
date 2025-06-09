// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

import {IAssetManager} from "src/policies/interfaces/utils/IAssetManager.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// @title  AssetManager
/// @notice This is a base contract for managing asset deposits and withdrawals. It is designed to be inherited by another contract.
abstract contract AssetManager is IAssetManager {
    using SafeTransferLib for ERC20;

    struct AssetConfiguration {
        bool isConfigured;
        address vault;
    }

    /// @notice Mapping of assets to a configuration
    mapping(address => AssetConfiguration) internal _assetConfigurations;

    /// @notice Mapping of assets and depositors to the number of shares they have deposited
    mapping(address => mapping(address => uint256)) internal _depositedShares;

    // ========== ACTION FUNCTIONS ========== //

    /// @notice Deposit assets into the configured vault
    /// @dev    This function will pull the assets from the caller and deposit them into the vault. If the vault is the zero address, the assets will be kept idle.
    ///
    ///         This function will revert if:
    ///         - The vault is not approved
    ///         - It is unable to pull the assets from the caller
    ///
    /// @param  asset_  The asset to deposit
    /// @param  amount_ The amount of assets to deposit
    /// @return shares  The number of shares received
    function _depositAsset(
        address asset_,
        address onBehalfOf_,
        uint256 amount_
    ) internal returns (uint256 shares) {
        // Validate that the vault is approved
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];
        if (!assetConfiguration.isConfigured) {
            revert AssetManager_NotConfigured();
        }

        // Pull the assets from the caller
        ERC20(asset_).safeTransferFrom(onBehalfOf_, address(this), amount_);

        // If the vault is the zero address, the asset is to be kept idle
        if (assetConfiguration.vault == address(0)) {
            shares = amount_;
        }
        // Otherwise, deposit the assets into the vault
        else {
            ERC20(asset_).safeApprove(assetConfiguration.vault, amount_);
            shares = ERC4626(assetConfiguration.vault).deposit(amount_, address(this));
        }

        // Update the shares deposited for the caller
        _depositedShares[asset_][onBehalfOf_] += amount_;

        emit AssetDeposited(asset_, onBehalfOf_, amount_, shares);
        return shares;
    }

    /// @notice Withdraw assets from the configured vault
    /// @dev    This function will withdraw the assets from the vault and send them to the caller. If the vault is the zero address, the assets will be kept idle.
    ///
    ///         This function will revert if:
    ///         - The vault is not approved
    ///
    /// @param  asset_      The asset to withdraw
    /// @param  onBehalfOf_ The address to withdraw the assets to
    /// @param  amount_     The amount of assets to withdraw
    /// @return shares      The number of shares withdrawn
    function _withdrawAsset(
        address asset_,
        address onBehalfOf_,
        uint256 amount_
    ) internal returns (uint256 shares) {
        // Validate that the vault is approved
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];
        if (!assetConfiguration.isConfigured) {
            revert AssetManager_NotConfigured();
        }

        // If the vault is the zero address, the asset is idle and kept in this contract
        if (assetConfiguration.vault == address(0)) {
            shares = amount_;
        }
        // Otherwise, withdraw the assets from the vault
        else {
            shares = ERC4626(assetConfiguration.vault).withdraw(
                amount_,
                onBehalfOf_,
                address(this)
            );
        }

        // Update the shares deposited for the caller
        _depositedShares[asset_][onBehalfOf_] -= shares;

        emit AssetWithdrawn(asset_, onBehalfOf_, amount_, shares);
        return shares;
    }

    /// @notice Get the number of shares deposited for an asset and depositor
    ///
    /// @param asset_       The asset to get the deposited shares for
    /// @param depositor_   The depositor to get the deposited shares for
    /// @return shares      The number of shares deposited
    function getDepositedShares(
        address asset_,
        address depositor_
    ) public view override returns (uint256 shares) {
        shares = _depositedShares[asset_][depositor_];
        return shares;
    }

    function getDepositedAssets(
        address asset_,
        address depositor_
    ) public view override returns (uint256 assets) {
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];

        // If the asset is not configured or there is no vault, the assets are kept idle and the shares = assets
        if (assetConfiguration.vault == address(0)) {
            assets = _depositedShares[asset_][depositor_];
        }
        // Otherwise, convert from shares to assets
        else {
            assets = ERC4626(assetConfiguration.vault).previewRedeem(
                _depositedShares[asset_][depositor_]
            );
        }

        return assets;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Configure an asset to be deposited into a vault
    /// @dev    This function will configure an asset to be deposited into a vault. If the vault is the zero address, the assets will be kept idle.
    ///
    ///         Note that the asset can only be configured once. This is to prevent the assets from being moved between vaults and exposing the deposited assets to the risk of theft.
    ///
    ///         This function will revert if:
    ///         - The asset is already configured
    ///         - The vault asset does not match the asset
    ///
    /// @param asset_  The asset to configure
    /// @param vault_  The vault to use
    function _configureAsset(address asset_, address vault_) internal {
        // Validate that the vault is not already approved
        if (_assetConfigurations[asset_].isConfigured) {
            revert AssetManager_VaultAlreadySet();
        }

        // Validate that the vault asset matches
        if (vault_ != address(0) && address(ERC4626(vault_).asset()) != asset_) {
            revert AssetManager_VaultAssetMismatch();
        }

        // Configure the asset
        _assetConfigurations[asset_] = AssetConfiguration({isConfigured: true, vault: vault_});
    }

    /// @notice Get the configuration for an asset
    ///
    /// @param  asset_      The asset to get the configuration for
    /// @return isConfigured  Whether the asset is approved
    /// @return vault       The vault to use
    function getAssetConfiguration(
        address asset_
    ) public view override returns (bool isConfigured, address vault) {
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];

        isConfigured = assetConfiguration.isConfigured;
        vault = assetConfiguration.vault;
        return (isConfigured, vault);
    }
}
