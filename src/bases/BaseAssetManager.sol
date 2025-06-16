// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.20;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// @title  BaseAssetManager
/// @notice This is a base contract for managing asset deposits and withdrawals. It is designed to be inherited by another contract.
///         This contract supports multiple assets, and can store them idle or in an ERC4626 vault (specified at the time of configuration). Once an approach is specified, it cannot be changed. This is to avoid the threat of a governance attack that shifts the deposited funds to a different vault in order to steal them.
///         Future versions of the contract could add support for more complex strategies and/or strategy migration, while addressing the concern of funds theft.
abstract contract BaseAssetManager is IAssetManager {
    using SafeTransferLib for ERC20;

    // ========== STATE VARIABLES ========== //

    /// @notice Array of configured assets
    IERC20[] internal _configuredAssets;

    /// @notice Mapping of assets to a configuration
    mapping(IERC20 asset => AssetConfiguration) internal _assetConfigurations;

    /// @notice Mapping of assets and operators to the number of shares they have deposited
    mapping(IERC20 asset => mapping(address operator => uint256 shares)) internal _operatorShares;

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
        IERC20 asset_,
        address depositor_,
        uint256 amount_
    ) internal onlyConfiguredAsset(asset_) returns (uint256 shares) {
        // Pull the assets from the depositor
        ERC20 asset = ERC20(address(asset_));
        asset.safeTransferFrom(depositor_, address(this), amount_);

        // If the vault is the zero address, the asset is to be kept idle
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];
        if (address(assetConfiguration.vault) == address(0)) {
            shares = amount_;
        }
        // Otherwise, deposit the assets into the vault
        else {
            asset.safeApprove(address(assetConfiguration.vault), amount_);
            shares = assetConfiguration.vault.deposit(amount_, address(this));
        }

        // Update the shares deposited by the caller (operator)
        _operatorShares[asset_][msg.sender] += shares;

        emit AssetDeposited(address(asset_), depositor_, msg.sender, amount_, shares);
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
        IERC20 asset_,
        address depositor_,
        uint256 amount_
    ) internal onlyConfiguredAsset(asset_) returns (uint256 shares) {
        // If the vault is the zero address, the asset is idle and kept in this contract
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];
        if (address(assetConfiguration.vault) == address(0)) {
            shares = amount_;
            ERC20(address(asset_)).safeTransfer(depositor_, amount_);
        }
        // Otherwise, withdraw the assets from the vault
        else {
            uint256 expShares = assetConfiguration.vault.previewWithdraw(amount_);
            uint256 operatorShares = _operatorShares[asset_][msg.sender];

            // If the last deposit is being withdrawn,
            // the ERC4626 vault's implementation of rounding up
            // or rounding down may result in a 1 wei difference
            // between the shares required to withdraw the amount
            // and the actual shares held.
            // In that scenario, we should use the operator's balance
            // of shares instead of the expected shares.
            if (expShares == operatorShares + 1) {
                shares = operatorShares;
            } else {
                shares = expShares;
            }

            // Redeem the shares for assets
            assetConfiguration.vault.redeem(shares, depositor_, address(this));
        }

        // Update the shares deposited by the caller (operator)
        _operatorShares[asset_][msg.sender] -= shares;

        emit AssetWithdrawn(address(asset_), depositor_, msg.sender, amount_, shares);
        return shares;
    }

    /// @inheritdoc IAssetManager
    function getOperatorAssets(
        IERC20 asset_,
        address operator_
    ) public view override returns (uint256 shares, uint256 sharesInAssets) {
        shares = _operatorShares[asset_][operator_];

        // Convert from shares to assets
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];
        if (address(assetConfiguration.vault) == address(0)) {
            sharesInAssets = shares;
        } else {
            sharesInAssets = assetConfiguration.vault.previewRedeem(shares);
        }

        return (shares, sharesInAssets);
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
    function _configureAsset(IERC20 asset_, address vault_) internal {
        // Validate that the asset is not the zero address
        if (address(asset_) == address(0)) {
            revert AssetManager_InvalidAsset();
        }

        // Validate that the vault is not already approved
        if (_assetConfigurations[asset_].isConfigured) {
            revert AssetManager_VaultAlreadySet();
        }

        // Validate that the vault asset matches
        if (vault_ != address(0) && address(IERC4626(vault_).asset()) != address(asset_)) {
            revert AssetManager_VaultAssetMismatch();
        }

        // Configure the asset
        _assetConfigurations[asset_] = AssetConfiguration({
            isConfigured: true,
            vault: IERC4626(vault_)
        });

        // Add the asset to the array of configured assets
        _configuredAssets.push(asset_);

        emit AssetConfigured(address(asset_), vault_);
    }

    function _isConfiguredAsset(IERC20 asset_) internal view returns (bool) {
        return _assetConfigurations[asset_].isConfigured;
    }

    modifier onlyConfiguredAsset(IERC20 asset_) {
        if (!_isConfiguredAsset(asset_)) revert AssetManager_NotConfigured();
        _;
    }

    /// @notice Get the configuration for an asset
    ///
    /// @param  asset_          The asset to get the configuration for
    /// @return configuration   The configuration for the asset
    function getAssetConfiguration(
        IERC20 asset_
    ) public view override returns (AssetConfiguration memory configuration) {
        return _assetConfigurations[asset_];
    }

    /// @inheritdoc IAssetManager
    function getConfiguredAssets() public view override returns (IERC20[] memory assets) {
        return _configuredAssets;
    }
}
