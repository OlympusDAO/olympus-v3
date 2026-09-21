// SPDX-License-Identifier: AGPL-3.0-only
// The repository pins solc 0.8.36 while sources retain their compatible minimum compiler versions.
// forge-lint: disable-next-line(pragma-inconsistent)
pragma solidity ^0.8.20;

// Interfaces
import {IERC7540Deposit, IERC7540Operator, IERC7540Redeem} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7540.sol";
import {IERC7575} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7575.sol";
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {ExcessivelySafeCall} from "@excessively-safe-call-0.0.1/ExcessivelySafeCall.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";

/// @title  BaseAssetManager
/// @notice This is a base contract for managing asset deposits and withdrawals. It is designed to be inherited by another contract.
///         This contract supports multiple assets, and can store them idle or in an ERC4626 vault (specified at the time of configuration). Once an approach is specified, it cannot be changed. This is to avoid the threat of a governance attack that shifts the deposited funds to a different vault in order to steal them.
///         Future versions of the contract could add support for more complex strategies and/or strategy migration, while addressing the concern of funds theft.
abstract contract BaseAssetManager is IAssetManagerV1_1, IERC165 {
    using ExcessivelySafeCall for address;
    using TransferHelper for ERC20;

    bytes4 internal constant _ERC7540_DEPOSIT_INTERFACE_ID = type(IERC7540Deposit).interfaceId;
    bytes4 internal constant _ERC7540_OPERATOR_INTERFACE_ID = type(IERC7540Operator).interfaceId;
    bytes4 internal constant _ERC7540_REDEEM_INTERFACE_ID = type(IERC7540Redeem).interfaceId;
    bytes4 internal constant _ERC7575_VAULT_INTERFACE_ID =
        type(IERC4626).interfaceId ^ type(IERC7575).interfaceId;
    uint16 internal constant _ERC20_BALANCE_RETURN_LENGTH = 32;

    // ========== STATE VARIABLES ========== //

    /// @notice Array of configured assets
    IERC20[] internal _configuredAssets;

    /// @notice Mapping of assets to a configuration
    mapping(IERC20 asset => AssetConfiguration) internal _assetConfigurations;

    /// @notice Mapping of configured assets to their immutable share token.
    mapping(IERC20 asset => IERC20 shareToken) internal _assetShareTokens;

    /// @notice Mapping of assets to explicit share-withdrawal requirements for non-standard vaults.
    mapping(IERC20 asset => bool required) internal _assetShareWithdrawalRequired;

    /// @notice Mapping of assets to outstanding credited principal consuming the shared cap.
    mapping(IERC20 asset => uint256 utilization) internal _assetDepositCapUtilization;

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
    /// @param  asset_                  The asset to deposit
    /// @param  depositor_              The depositor
    /// @param  amount_                 The amount of assets to deposit
    /// @param  enforceDepositChecks_   Whether to enforce the minimum deposit requirement and deposit cap
    /// @return actualAmount    The actual amount of assets redeemable by the shares
    /// @return shares          The number of shares received
    function _depositAsset(
        IERC20 asset_,
        address depositor_,
        uint256 amount_,
        bool enforceDepositChecks_
    ) internal onlyConfiguredAsset(asset_) returns (uint256 actualAmount, uint256 shares) {
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];

        // Validate that the deposit meets the minimum deposit requirement
        if (enforceDepositChecks_ && amount_ < assetConfiguration.minimumDeposit) {
            revert AssetManager_MinimumDepositNotMet(
                address(asset_),
                amount_,
                assetConfiguration.minimumDeposit
            );
        }

        // Pull the assets from the depositor
        ERC20 asset = ERC20(address(asset_));
        // The calling operator is authorized to pull from the depositor through DepositManager's
        // receipt-token and role checks; the depositor is intentionally distinct from msg.sender.
        // forge-lint: disable-next-line(arbitrary-send-erc20)
        asset.safeTransferFromExact(depositor_, address(this), amount_);

        address vaultAddress = assetConfiguration.vault;
        // If the vault is the zero address, the asset is to be kept idle.
        if (vaultAddress == address(0)) {
            shares = amount_;
            if (shares == 0) revert AssetManager_ZeroAmount();
            actualAmount = amount_;
        } else {
            // Otherwise, deposit the assets into the configured vault. The configured share-token
            // balance increase is authoritative for custody accounting.
            IERC4626 vault = IERC4626(vaultAddress);
            IERC20 shareToken = _assetShareTokens[asset_];
            uint256 shareBalanceBefore = shareToken.balanceOf(address(this));
            asset.safeApprove(vaultAddress, amount_);

            // DepositManager guards every entry point that reaches this call. The shares cannot be
            // recorded before the vault returns their authoritative amount.
            // forge-lint: disable-next-line(reentrancy-no-eth)
            shares = vault.deposit(amount_, address(this));
            if (shares == 0) revert AssetManager_ZeroAmount();

            uint256 receivedShares = shareToken.balanceOf(address(this)) - shareBalanceBefore;
            if (receivedShares != shares) {
                revert AssetManager_InexactSharesReceived(
                    address(asset_),
                    address(shareToken),
                    shares,
                    receivedShares
                );
            }

            // Credit only the assets represented by the shares actually received. Async-redeem
            // vaults must use convertToAssets because ERC-7540 requires previewRedeem to revert.
            actualAmount = _convertSharesToAssets(vault, shares);
        }

        // The credited amount after vault conversion is the authoritative principal exposure.
        // Re-read the cap after the external vault call so a callback cannot make the check stale.
        if (enforceDepositChecks_ && actualAmount != 0) {
            _validateAssetDepositCap(asset_, actualAmount);
            _assetDepositCapUtilization[asset_] += actualAmount;
        }

        // Update the shares deposited by the caller (operator).
        _operatorShares[_getOperatorKey(asset_, msg.sender)] += shares;
        emit AssetDeposited(address(asset_), depositor_, msg.sender, actualAmount, shares);
    }

    /// @notice Withdraw assets or transfer the corresponding vault shares
    /// @dev `amount_` is always denominated in the underlying asset. Share output rounds down via
    ///      the configured vault's `convertToShares` implementation.
    /// @param asset_ The underlying asset in which the request is denominated
    /// @param depositor_ The output-token recipient
    /// @param amount_ The requested amount in underlying-asset units
    /// @param withdrawAsShares_ Whether to transfer vault shares instead of redeeming them
    /// @return shares The exact custody shares transferred or redeemed (can be 0)
    /// @return tokenOut The output token
    /// @return amountOut The amount transferred in `tokenOut` units (can be 0)
    function _withdrawAsset(
        IERC20 asset_,
        address depositor_,
        uint256 amount_,
        bool withdrawAsShares_
    ) internal returns (uint256 shares, IERC20 tokenOut, uint256 amountOut) {
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];
        if (!assetConfiguration.isConfigured) revert AssetManager_NotConfigured();
        tokenOut = _getAssetWithdrawalToken(asset_, assetConfiguration, withdrawAsShares_);

        // If the vault is the zero address, the asset is idle and kept in this contract.
        if (assetConfiguration.vault == address(0)) {
            shares = amount_;
            amountOut = amount_;
            _operatorShares[_getOperatorKey(asset_, msg.sender)] -= shares;
            ERC20(address(asset_)).safeTransfer(depositor_, amount_);
            emit AssetWithdrawn(address(asset_), depositor_, msg.sender, amountOut, shares);
            return (shares, tokenOut, amountOut);
        }

        // Otherwise, convert the underlying-denominated request into raw vault share units.
        IERC4626 vault = IERC4626(assetConfiguration.vault);
        // amount_ uses the underlying asset's decimal scale. convertToShares() returns raw shares.
        shares = vault.convertToShares(amount_);
        if (withdrawAsShares_) {
            if (shares != 0) {
                _operatorShares[_getOperatorKey(asset_, msg.sender)] -= shares;
                amountOut = shares;
                ERC20(address(tokenOut)).safeTransfer(depositor_, shares);
            }
            _emitShareWithdrawal(asset_, depositor_, amount_, tokenOut, amountOut);
            return (shares, tokenOut, amountOut);
        }

        // Underlying mode values shares through the live conversion route, then calls redeem so the
        // vault's native error bubbles if redemption changed to asynchronous after configuration.
        // A vault may also map nonzero shares to zero assets; do not burn shares for no output.
        if (shares == 0 || _convertSharesToAssets(vault, shares) == 0) {
            emit AssetWithdrawn(address(asset_), depositor_, msg.sender, 0, 0);
            return (0, tokenOut, 0);
        }

        _operatorShares[_getOperatorKey(asset_, msg.sender)] -= shares;
        amountOut = vault.redeem(shares, depositor_, address(this));
        emit AssetWithdrawn(address(asset_), depositor_, msg.sender, amountOut, shares);
    }

    /// @notice Emits the implementation-specific result of a share-mode withdrawal request.
    function _emitShareWithdrawal(
        IERC20 asset_,
        address recipient_,
        uint256 requestedAmount_,
        IERC20 tokenOut_,
        uint256 amountOut_
    ) internal virtual;

    /// @inheritdoc IAssetManager
    function getOperatorAssets(
        IERC20 asset_,
        address operator_
    ) public view override returns (uint256 shares, uint256 sharesInAssets) {
        shares = _operatorShares[_getOperatorKey(asset_, operator_)];

        // Convert from shares to assets
        AssetConfiguration memory assetConfiguration = _assetConfigurations[asset_];
        if (assetConfiguration.vault == address(0)) return (shares, shares);
        sharesInAssets = _convertSharesToAssets(IERC4626(assetConfiguration.vault), shares);

        return (shares, sharesInAssets);
    }

    /// @notice Get the key for the operator shares
    function _getOperatorKey(IERC20 asset_, address operator_) internal pure returns (bytes32) {
        /// forge-lint: disable-next-line(asm-keccak256)
        return keccak256(abi.encode(address(asset_), operator_));
    }

    /// @notice Validates a positive credited-principal increase against the live shared cap.
    function _validateAssetDepositCap(IERC20 asset_, uint256 credit_) internal view {
        uint256 utilization = _assetDepositCapUtilization[asset_];
        uint256 depositCap = _assetConfigurations[asset_].depositCap;
        if (utilization > depositCap || credit_ > depositCap - utilization) {
            revert AssetManager_DepositCapExceeded(address(asset_), utilization, depositCap);
        }
    }

    /// @notice Releases shared cap utilization when receipt-backed principal is destroyed.
    function _decreaseAssetDepositCapUtilization(IERC20 asset_, uint256 amount_) internal {
        _assetDepositCapUtilization[asset_] -= amount_;
    }

    /// @notice Returns whether the vault currently advertises asynchronous redemption.
    /// @dev This result selects `convertToAssets` instead of the synchronous-only `previewRedeem`.
    ///      An underlying withdrawal still calls `redeem`, so the vault's native error bubbles if
    ///      its redemption behavior changed to asynchronous after configuration.
    /// @param vault_ The configured vault entry point.
    /// @return True when redemption currently uses an asynchronous request lifecycle.
    function _isVaultAsyncRedeem(IERC4626 vault_) internal view returns (bool) {
        return ERC165Checker.supportsInterface(address(vault_), _ERC7540_REDEEM_INTERFACE_ID);
    }

    /// @notice Converts vault-share units into underlying-asset units.
    /// @dev ERC-7540 requires `previewRedeem` to revert for asynchronous redemption, so those
    ///      vaults use the non-preview conversion function.
    /// @param vault_ The configured vault entry point.
    /// @param shares_ The quantity in raw share-token units.
    /// @return assets The current value in underlying-asset units.
    function _convertSharesToAssets(
        IERC4626 vault_,
        uint256 shares_
    ) internal view returns (uint256 assets) {
        if (_isVaultAsyncRedeem(vault_)) return vault_.convertToAssets(shares_);
        return vault_.previewRedeem(shares_);
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

        // Validate that minimum deposit does not exceed deposit cap
        if (minimumDeposit_ > depositCap_) {
            revert AssetManager_MinimumDepositExceedsDepositCap(
                address(asset_),
                minimumDeposit_,
                depositCap_
            );
        }

        address vaultAddress = address(vault_);
        // Idle custody uses the asset itself for one-to-one share accounting. Ordinary ERC-4626
        // vaults use the vault token, while ERC-7575 vaults replace it with their reported share().
        IERC20 shareToken = asset_;
        if (vaultAddress != address(0)) {
            shareToken = _resolveVaultShareToken(asset_, vault_);
        }

        // Every configured route needs disjoint custody-token identities. Reusing an asset, vault,
        // or external share token would make its physical balance ambiguous between configurations.
        _validateCustodyTokenIdentities(asset_, vaultAddress, shareToken);

        // Configure the asset
        _assetConfigurations[asset_] = AssetConfiguration({
            isConfigured: true,
            vault: vaultAddress,
            depositCap: depositCap_,
            minimumDeposit: minimumDeposit_
        });
        _assetShareTokens[asset_] = shareToken;

        // Add the asset to the array of configured assets
        _configuredAssets.push(asset_);

        emit AssetConfigured(address(asset_), vaultAddress);
        emit AssetDepositCapSet(address(asset_), depositCap_);
        emit AssetMinimumDepositSet(address(asset_), minimumDeposit_);
        emit AssetShareTokenConfigured(address(asset_), address(shareToken));
    }

    /// @notice Resolves and validates the share token for a non-idle vault.
    /// @dev Standard ERC-4626 vaults use the vault address. ERC-7575 vaults use `share()`.
    ///      Asynchronous deposits are unsupported, and asynchronous redemption additionally
    ///      requires ERC-7540 operator support plus ERC-7575 share discovery.
    /// @param asset_ The underlying asset being configured.
    /// @param vault_ The nonzero vault entry point.
    /// @return shareToken The ERC-20 token that represents vault shares.
    function _resolveVaultShareToken(
        IERC20 asset_,
        IERC4626 vault_
    ) internal view returns (IERC20 shareToken) {
        address vaultAddress = address(vault_);
        if (address(vault_.asset()) != address(asset_)) revert AssetManager_VaultAssetMismatch();
        if (ERC165Checker.supportsInterface(vaultAddress, _ERC7540_DEPOSIT_INTERFACE_ID)) {
            revert AssetManager_InvalidVaultCapabilities(address(asset_), vaultAddress);
        }

        bool supportsERC7575 = ERC165Checker.supportsInterface(
            vaultAddress,
            _ERC7575_VAULT_INTERFACE_ID
        );
        if (
            _isVaultAsyncRedeem(vault_) &&
            (!supportsERC7575 ||
                !ERC165Checker.supportsInterface(vaultAddress, _ERC7540_OPERATOR_INTERFACE_ID))
        ) revert AssetManager_InvalidVaultCapabilities(address(asset_), vaultAddress);
        if (!supportsERC7575) return IERC20(vaultAddress);

        try IERC7575(vaultAddress).share() returns (address shareTokenAddress) {
            shareToken = IERC20(shareTokenAddress);
        } catch {
            revert AssetManager_InvalidShareToken(address(asset_), address(0));
        }

        (bool succeeded, bytes memory result) = address(shareToken).excessivelySafeStaticCall(
            gasleft(),
            _ERC20_BALANCE_RETURN_LENGTH,
            abi.encodeCall(IERC20.balanceOf, (address(this)))
        );
        if (!succeeded || result.length < _ERC20_BALANCE_RETURN_LENGTH) {
            revert AssetManager_InvalidShareToken(address(asset_), address(shareToken));
        }
    }

    /// @notice Rejects custody-token identities already attributed to another asset route.
    /// @param asset_ The new route's underlying asset.
    /// @param vault_ The new route's vault, or zero for idle custody.
    /// @param shareToken_ The new route's resolved share token.
    function _validateCustodyTokenIdentities(
        IERC20 asset_,
        address vault_,
        IERC20 shareToken_
    ) internal view {
        if (vault_ == address(asset_)) {
            revert AssetManager_TokenAlreadyManaged(address(asset_));
        }
        if (_isManagedToken(address(asset_))) {
            revert AssetManager_TokenAlreadyManaged(address(asset_));
        }
        if (vault_ != address(0) && _isManagedToken(vault_)) {
            revert AssetManager_TokenAlreadyManaged(vault_);
        }
        if (vault_ == address(0) || address(shareToken_) == vault_) return;
        if (address(shareToken_) == address(asset_) || _isManagedToken(address(shareToken_))) {
            revert AssetManager_TokenAlreadyManaged(address(shareToken_));
        }
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

    /// @notice Returns whether a token is part of any configured custody route.
    function _isManagedToken(address token_) internal view returns (bool) {
        uint256 assetCount = _configuredAssets.length;
        for (uint256 i; i < assetCount; ++i) {
            IERC20 configuredAsset = _configuredAssets[i];
            if (token_ == address(configuredAsset)) return true;
            if (token_ == _assetConfigurations[configuredAsset].vault) return true;
            if (token_ == address(_assetShareTokens[configuredAsset])) return true;
        }
        return false;
    }

    function _onlyConfiguredAsset(IERC20 asset_) internal view {
        if (!_isConfiguredAsset(asset_)) revert AssetManager_NotConfigured();
    }

    modifier onlyConfiguredAsset(IERC20 asset_) {
        _onlyConfiguredAsset(asset_);
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

    /// @inheritdoc IAssetManagerV1_1
    function getAssetDepositCapStatus(
        IERC20 asset_
    ) public view override returns (AssetDepositCapStatus memory status) {
        status.depositCap = _assetConfigurations[asset_].depositCap;
        status.utilization = _assetDepositCapUtilization[asset_];
        return status;
    }

    /// @notice Validates the requested withdrawal mode before action-specific external calls.
    /// @dev Unconfigured assets remain subject to each entry point's existing error ordering.
    function _validateWithdrawalMode(IERC20 asset_, bool withdrawAsShares_) internal view {
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (!configuration.isConfigured) return;
        _validateWithdrawalMode(asset_, configuration, withdrawAsShares_);
    }

    /// @notice Validates a withdrawal mode against an already-loaded asset configuration.
    /// @return tokenOut The token delivered by a valid withdrawal mode.
    function _validateWithdrawalMode(
        IERC20 asset_,
        AssetConfiguration memory configuration_,
        bool withdrawAsShares_
    ) internal view returns (IERC20 tokenOut) {
        tokenOut = _getAssetWithdrawalToken(asset_, configuration_, withdrawAsShares_);
        if (!withdrawAsShares_ && _isAssetShareWithdrawalRequired(asset_, configuration_)) {
            revert AssetManager_RequiresWithdrawAsShares(address(asset_), configuration_.vault);
        }
    }

    /// @notice Resolves the token transferred for an already-loaded asset configuration.
    function _getAssetWithdrawalToken(
        IERC20 asset_,
        AssetConfiguration memory configuration_,
        bool withdrawAsShares_
    ) internal view returns (IERC20 tokenOut) {
        if (!withdrawAsShares_) return asset_;
        if (configuration_.vault == address(0)) {
            revert AssetManager_VaultRequired(address(asset_));
        }
        return _assetShareTokens[asset_];
    }

    /// @inheritdoc IAssetManagerV1_1
    function getAssetWithdrawalToken(
        IERC20 asset_,
        bool withdrawAsShares_
    ) public view override returns (IERC20 tokenOut) {
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (!configuration.isConfigured) revert AssetManager_NotConfigured();
        return _getAssetWithdrawalToken(asset_, configuration, withdrawAsShares_);
    }

    /// @inheritdoc IAssetManagerV1_1
    function isAssetShareWithdrawalRequired(
        IERC20 asset_
    ) public view override returns (bool required) {
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (!configuration.isConfigured) revert AssetManager_NotConfigured();
        return _isAssetShareWithdrawalRequired(asset_, configuration);
    }

    /// @notice Returns the effective share-withdrawal requirement for a loaded configuration.
    function _isAssetShareWithdrawalRequired(
        IERC20 asset_,
        AssetConfiguration memory configuration_
    ) internal view returns (bool required) {
        if (_assetShareWithdrawalRequired[asset_]) return true;
        if (configuration_.vault == address(0)) return false;
        return _isVaultAsyncRedeem(IERC4626(configuration_.vault));
    }

    /// @notice Updates the explicit requirement used for non-standard asynchronous vaults.
    function _setAssetShareWithdrawalRequired(IERC20 asset_, bool required_) internal {
        validateAssetShareWithdrawalRequired(asset_, required_);
        _assetShareWithdrawalRequired[asset_] = required_;
        emit AssetShareWithdrawalRequirementSet(address(asset_), required_);
    }

    /// @inheritdoc IAssetManagerV1_1
    function validateAssetShareWithdrawalRequired(
        IERC20 asset_,
        bool required_
    ) public view override {
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (!configuration.isConfigured) revert AssetManager_NotConfigured();
        if (required_ && configuration.vault == address(0)) {
            revert AssetManager_VaultRequired(address(asset_));
        }
        if (
            !required_ &&
            configuration.vault != address(0) &&
            _isVaultAsyncRedeem(IERC4626(configuration.vault))
        ) {
            revert AssetManager_RequiresWithdrawAsShares(address(asset_), configuration.vault);
        }
    }

    /// @inheritdoc IAssetManagerV1_1
    /// @dev Reverts if:
    ///      - The asset is not configured.
    ///      - Share output is requested for idle custody.
    ///      - Underlying output is requested while the vault advertises asynchronous redemption.
    function validateAssetWithdrawAsShares(
        IERC20 asset_,
        bool withdrawAsShares_
    ) public view override {
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (!configuration.isConfigured) revert AssetManager_NotConfigured();
        _validateWithdrawalMode(asset_, configuration, withdrawAsShares_);
    }

    /// @inheritdoc IAssetManager
    function getConfiguredAssets() public view override returns (IERC20[] memory assets) {
        return _configuredAssets;
    }

    // ========== ERC165 ========== //

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IAssetManager).interfaceId ||
            interfaceId == type(IAssetManagerV1_1).interfaceId;
    }
}
