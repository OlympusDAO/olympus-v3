// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.20;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";

/// @title  BaseAssetManager
/// @notice This is a base contract for managing asset deposits and withdrawals. It is designed to be inherited by another contract.
///         This contract supports multiple assets, and can store them idle or in an ERC4626 vault (specified at the time of configuration). Once an approach is specified, it cannot be changed. This is to avoid the threat of a governance attack that shifts the deposited funds to a different vault in order to steal them.
///         Future versions of the contract could add support for more complex strategies and/or strategy migration, while addressing the concern of funds theft.
abstract contract BaseAssetManager is IAssetManager {
    using TransferHelper for ERC20;

    // ========== STATE VARIABLES ========== //

    /// @notice Array of configured assets
    IERC20[] internal _configuredAssets;

    /// @notice Mapping of assets to a configuration
    mapping(IERC20 asset => AssetConfiguration) internal _assetConfigurations;

    /// @notice Mapping of assets and operators to the number of shares they have deposited
    mapping(bytes32 operatorKey => uint256 shares) internal _operatorShares;

    // ========== ACTION FUNCTIONS ========== //

    /// @notice Deposit assets into the configured vault
    /// @dev    This function will pull the assets from the depositor and deposit them into the vault. If the vault is the zero address, the assets will be kept idle.
    ///
    ///         To avoid susceptibility to ERC777 re-entrancy, this function should be called before any state changes.
    ///
    ///         When an ERC4626 vault is configured for an asset, the amount of assets that can be withdrawn may be 1 less than what was originally deposited. To be conservative, this function returns the actual amount.
    ///
    ///         This function will revert if:
    ///         - The vault is not approved
    ///         - It is unable to pull the assets from the depositor
    ///         - The minimum deposit requirement is not met
    ///         - Adding the deposit would exceed the deposit cap
    ///         - Zero shares would be received from the vault
    ///
    /// @param  asset_          The asset to deposit
    /// @param  depositor_      The depositor
    /// @param  amount_         The amount of assets to deposit
    /// @return actualAmount    The actual amount of assets redeemable by the shares
    /// @return shares          The number of shares received
    function _depositAsset(
        IERC20 asset_,
        address depositor_,
        uint256 amount_
    ) internal onlyConfiguredAsset(asset_) returns (uint256 actualAmount, uint256 shares) {
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];

        // Validate that the deposit meets the minimum deposit requirement
        if (amount_ < assetConfiguration.minimumDeposit) {
            revert AssetManager_MinimumDepositNotMet(
                address(asset_),
                amount_,
                assetConfiguration.minimumDeposit
            );
        }

        // Validate that adding the deposit will not exceed the deposit cap
        {
            (, uint256 assetAmountBefore) = getOperatorAssets(asset_, msg.sender);
            if (assetAmountBefore + amount_ > assetConfiguration.depositCap) {
                revert AssetManager_DepositCapExceeded(
                    address(asset_),
                    assetAmountBefore,
                    assetConfiguration.depositCap
                );
            }
        }

        // Pull the assets from the depositor
        ERC20 asset = ERC20(address(asset_));
        uint256 balanceBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(depositor_, address(this), amount_);
        // Revert if the asset is a fee-on-transfer token
        if (asset.balanceOf(address(this)) != balanceBefore + amount_) {
            revert AssetManager_InvalidAsset();
        }

        // If the vault is the zero address, the asset is to be kept idle
        if (assetConfiguration.vault == address(0)) {
            shares = amount_;
            actualAmount = amount_;
        }
        // Otherwise, deposit the assets into the vault
        else {
            IERC4626 vault = IERC4626(assetConfiguration.vault);
            asset.safeApprove(address(vault), amount_);
            shares = vault.deposit(amount_, address(this));

            // The amount of assets redeemable by the shares can be different from the amount deposited
            // due to rounding errors in the ERC4626 vault
            // To avoid minting more receipt tokens than the actual redeemable amount,
            // we should use the previewRedeem function to get the actual amount of assets redeemable by the shares.
            actualAmount = vault.previewRedeem(shares);
        }

        // Amount of shares must be non-zero
        if (shares == 0) revert AssetManager_ZeroAmount();

        // Update the shares deposited by the caller (operator)
        _operatorShares[_getOperatorKey(asset_, msg.sender)] += shares;

        emit AssetDeposited(address(asset_), depositor_, msg.sender, actualAmount, shares);
        return (actualAmount, shares);
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
    ) internal onlyConfiguredAsset(asset_) returns (uint256 shares, uint256 assetAmount) {
        // If the vault is the zero address, the asset is idle and kept in this contract
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];
        if (assetConfiguration.vault == address(0)) {
            shares = amount_;
            assetAmount = amount_;
            ERC20(address(asset_)).safeTransfer(depositor_, amount_);
        }
        // Otherwise, withdraw the assets from the vault
        else {
            IERC4626 vault = IERC4626(assetConfiguration.vault);

            // Use convertToShares(), which rounds down, to determine the number of shares to redeem from the vault
            // This may result in the depositor receiving a few less wei,
            // but ensures that the vault remains solvent
            shares = vault.convertToShares(amount_);

            // Amount of shares must be non-zero
            if (shares == 0) revert AssetManager_ZeroAmount();

            assetAmount = vault.redeem(shares, depositor_, address(this));
        }

        // Update the shares deposited by the caller (operator)
        _operatorShares[_getOperatorKey(asset_, msg.sender)] -= shares;

        emit AssetWithdrawn(address(asset_), depositor_, msg.sender, assetAmount, shares);
        return (shares, assetAmount);
    }

    /// @inheritdoc IAssetManager
    function getOperatorAssets(
        IERC20 asset_,
        address operator_
    ) public view override returns (uint256 shares, uint256 sharesInAssets) {
        shares = _operatorShares[_getOperatorKey(asset_, operator_)];

        // Convert from shares to assets
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];
        if (assetConfiguration.vault == address(0)) {
            sharesInAssets = shares;
        } else {
            sharesInAssets = IERC4626(assetConfiguration.vault).previewRedeem(shares);
        }

        return (shares, sharesInAssets);
    }

    /// @notice Get the key for the operator shares
    function _getOperatorKey(IERC20 asset_, address operator_) internal pure returns (bytes32) {
        return keccak256(abi.encode(address(asset_), operator_));
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
    ///         - The minimum deposit exceeds the deposit cap
    ///
    /// @param asset_          The asset to configure
    /// @param vault_          The vault to use
    /// @param depositCap_     The deposit cap of the asset
    /// @param minimumDeposit_ The minimum deposit amount for the asset
    function _addAsset(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_,
        uint256 minimumDeposit_
    ) internal {
        // Validate that the asset is not the zero address
        if (address(asset_) == address(0)) {
            revert AssetManager_InvalidAsset();
        }

        // Validate that the vault is not already configured
        if (_assetConfigurations[asset_].isConfigured) {
            revert AssetManager_AssetAlreadyConfigured();
        }

        // Validate that the vault asset matches
        if (address(vault_) != address(0) && address(vault_.asset()) != address(asset_)) {
            revert AssetManager_VaultAssetMismatch();
        }

        // Validate that minimum deposit does not exceed deposit cap
        if (minimumDeposit_ > depositCap_) {
            revert AssetManager_MinimumDepositExceedsDepositCap(
                address(asset_),
                minimumDeposit_,
                depositCap_
            );
        }

        // Configure the asset
        _assetConfigurations[asset_] = AssetConfiguration({
            isConfigured: true,
            vault: address(vault_),
            depositCap: depositCap_,
            minimumDeposit: minimumDeposit_
        });

        // Add the asset to the array of configured assets
        _configuredAssets.push(asset_);

        emit AssetConfigured(address(asset_), address(vault_));
        emit AssetDepositCapSet(address(asset_), depositCap_);
        emit AssetMinimumDepositSet(address(asset_), minimumDeposit_);
    }

    /// @notice Set the deposit cap for an asset
    /// @dev    This function will set the deposit cap for an asset.
    ///
    ///         This function will revert if:
    ///         - The asset is not configured
    ///         - The deposit cap is less than the minimum deposit
    ///
    /// @param asset_          The asset to set the deposit cap for
    /// @param depositCap_     The deposit cap to set for the asset
    function _setAssetDepositCap(IERC20 asset_, uint256 depositCap_) internal {
        // Validate that the asset is configured
        if (!_isConfiguredAsset(asset_)) revert AssetManager_NotConfigured();

        // Validate that deposit cap is not less than minimum deposit
        uint256 minimumDeposit = _assetConfigurations[asset_].minimumDeposit;
        if (depositCap_ < minimumDeposit) {
            revert AssetManager_MinimumDepositExceedsDepositCap(
                address(asset_),
                minimumDeposit,
                depositCap_
            );
        }

        // Set the deposit cap
        _assetConfigurations[asset_].depositCap = depositCap_;
        emit AssetDepositCapSet(address(asset_), depositCap_);
    }

    /// @notice Set the minimum deposit for an asset
    /// @dev    This function will set the minimum deposit for an asset.
    ///
    ///         The minimum deposit prevents insolvency issues that can occur when small deposits
    ///         accrue large amounts of yield. When claiming yield on such deposits, all vault shares
    ///         may be burned while liabilities remain, causing the DepositManager_Insolvent error
    ///         and blocking subsequent yield claims.
    ///
    ///         This function will revert if:
    ///         - The asset is not configured
    ///         - The minimum deposit exceeds the deposit cap
    ///
    /// @param asset_           The asset to set the minimum deposit for
    /// @param minimumDeposit_  The minimum deposit to set for the asset
    function _setAssetMinimumDeposit(IERC20 asset_, uint256 minimumDeposit_) internal {
        // Validate that the asset is configured
        if (!_isConfiguredAsset(asset_)) revert AssetManager_NotConfigured();

        // Validate that minimum deposit does not exceed deposit cap
        uint256 depositCap = _assetConfigurations[asset_].depositCap;
        if (minimumDeposit_ > depositCap) {
            revert AssetManager_MinimumDepositExceedsDepositCap(
                address(asset_),
                minimumDeposit_,
                depositCap
            );
        }

        // Set the minimum deposit
        _assetConfigurations[asset_].minimumDeposit = minimumDeposit_;
        emit AssetMinimumDepositSet(address(asset_), minimumDeposit_);
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

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IAssetManager).interfaceId;
    }
}
