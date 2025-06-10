// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

import {IAssetManager} from "src/interfaces/IAssetManager.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// @title  AssetManager
/// @notice This is a base contract for managing asset deposits and withdrawals. It is designed to be inherited by another contract.
abstract contract AssetManager is IAssetManager {
    using SafeTransferLib for ERC20;

    struct AssetConfiguration {
        bool isConfigured;
        ERC4626 vault;
    }

    /// @notice Mapping of assets to a configuration
    mapping(ERC20 => AssetConfiguration) internal _assetConfigurations;

    /// @notice Mapping of assets and operators to the number of shares they have deposited
    mapping(ERC20 => mapping(address => uint256)) internal _depositedShares;

    // ========== ACTION FUNCTIONS ========== //

    /// @notice Deposit assets into the configured vault
    /// @dev    This function will pull the assets from the depositor and deposit them into the vault. If the vault is the zero address, the assets will be kept idle.
    ///
    ///         This function will revert if:
    ///         - The vault is not approved
    ///         - It is unable to pull the assets from the depositor
    ///
    /// @param  asset_      The asset to deposit
    /// @param  depositor_  The depositor
    /// @param  amount_     The amount of assets to deposit
    /// @return shares      The number of shares received
    function _depositAsset(
        address asset_,
        address depositor_,
        uint256 amount_
    ) internal returns (uint256 shares) {
        // Validate that the vault is approved
        AssetConfiguration memory assetConfiguration = _assetConfigurations[ERC20(asset_)];
        if (!assetConfiguration.isConfigured) {
            revert AssetManager_NotConfigured();
        }

        // Pull the assets from the depositor
        ERC20 asset = ERC20(asset_);
        asset.safeTransferFrom(depositor_, address(this), amount_);

        // If the vault is the zero address, the asset is to be kept idle
        if (address(assetConfiguration.vault) == address(0)) {
            shares = amount_;
        }
        // Otherwise, deposit the assets into the vault
        else {
            asset.safeApprove(address(assetConfiguration.vault), amount_);
            shares = assetConfiguration.vault.deposit(amount_, address(this));
        }

        // Update the shares deposited by the caller (operator)
        _depositedShares[asset][msg.sender] += amount_;

        emit AssetDeposited(asset_, depositor_, msg.sender, amount_, shares);
        return shares;
    }

    /// @notice Withdraw assets from the configured vault
    /// @dev    This function will withdraw the assets from the vault and send them to the depositor. If the vault is the zero address, the assets will be kept idle.
    ///
    ///         This function will revert if:
    ///         - The vault is not approved
    ///
    /// @param  asset_      The asset to withdraw
    /// @param  depositor_  The depositor
    /// @param  amount_     The amount of assets to withdraw
    /// @return shares      The number of shares withdrawn
    function _withdrawAsset(
        address asset_,
        address depositor_,
        uint256 amount_
    ) internal returns (uint256 shares) {
        // Validate that the vault is approved
        AssetConfiguration memory assetConfiguration = _assetConfigurations[ERC20(asset_)];
        if (!assetConfiguration.isConfigured) {
            revert AssetManager_NotConfigured();
        }

        // If the vault is the zero address, the asset is idle and kept in this contract
        if (address(assetConfiguration.vault) == address(0)) {
            shares = amount_;
        }
        // Otherwise, withdraw the assets from the vault
        else {
            shares = assetConfiguration.vault.withdraw(amount_, depositor_, address(this));
        }

        // Update the shares deposited by the caller (operator)
        _depositedShares[ERC20(asset_)][msg.sender] -= shares;

        emit AssetWithdrawn(asset_, depositor_, msg.sender, amount_, shares);
        return shares;
    }

    /// @inheritdoc IAssetManager
    function getDepositedShares(
        address asset_,
        address operator_
    ) public view override returns (uint256 shares) {
        shares = _depositedShares[ERC20(asset_)][operator_];
        return shares;
    }

    /// @inheritdoc IAssetManager
    function getDepositedAssets(
        address asset_,
        address operator_
    ) public view override returns (uint256 assets) {
        AssetConfiguration memory assetConfiguration = _assetConfigurations[ERC20(asset_)];

        // If the asset is not configured or there is no vault, the assets are kept idle and the shares = assets
        if (address(assetConfiguration.vault) == address(0)) {
            assets = _depositedShares[ERC20(asset_)][operator_];
        }
        // Otherwise, convert from shares to assets
        else {
            assets = assetConfiguration.vault.previewRedeem(
                _depositedShares[ERC20(asset_)][operator_]
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
        if (_assetConfigurations[ERC20(asset_)].isConfigured) {
            revert AssetManager_VaultAlreadySet();
        }

        // Validate that the vault asset matches
        if (vault_ != address(0) && address(ERC4626(vault_).asset()) != asset_) {
            revert AssetManager_VaultAssetMismatch();
        }

        // Configure the asset
        _assetConfigurations[ERC20(asset_)] = AssetConfiguration({
            isConfigured: true,
            vault: ERC4626(vault_)
        });

        emit AssetConfigured(asset_, vault_);
    }

    /// @notice Get the configuration for an asset
    ///
    /// @param  asset_      The asset to get the configuration for
    /// @return isConfigured  Whether the asset is approved
    /// @return vault       The vault to use
    function getAssetConfiguration(
        address asset_
    ) public view override returns (bool isConfigured, address vault) {
        AssetConfiguration memory assetConfiguration = _assetConfigurations[ERC20(asset_)];

        isConfigured = assetConfiguration.isConfigured;
        vault = address(assetConfiguration.vault);
        return (isConfigured, vault);
    }
}
