// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IERC4626} from "@openzeppelin-5.3.0/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-5.3.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC7540Deposit} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7540.sol";
import {IERC7575} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7575.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {Errors} from "src/libraries/Errors.sol";
import {SafeCall} from "src/libraries/SafeCall.sol";
import {YieldRepurchaseFacilityV2VaultLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2VaultLib.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";

// Modules
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";

/// @title YieldRepurchaseFacilityV2AssetRegistryLib
/// @notice An external library that owns the asset registry of the
///         YieldRepurchaseFacilityV2 (the per-vault configurations, the vault list, the
///         reserve lookup, and the backing vault designation) and validates the
///         registrations and the per-asset mode changes.
/// @dev The library is deployed separately and reached through `DELEGATECALL`, so the
///      storage parameters reference the calling facility's storage, the facility is
///      `address(this)`, and the emitted events and the errors belong to the facility
///      interface.
library YieldRepurchaseFacilityV2AssetRegistryLib {
    /// @notice Byte length of the single word a vault probe must return.
    uint16 private constant _PROBE_RETURN_LENGTH = 32;

    /// @notice The ERC165 identifier of an ERC7575 vault (`0x2f0a18c5`): the ERC4626
    ///         vault functions combined with `share()`.
    bytes4 private constant _ERC7575_VAULT_INTERFACE_ID =
        type(IERC4626).interfaceId ^ type(IERC7575).interfaceId;

    /// @notice The asset registry of the facility.
    /// @param configs The configuration and accounting of each registered vault.
    /// @param vaults The ordered list of the registered vault addresses.
    /// @param reserveVaults The registered vault of each reserve token, or the zero
    ///        address when the token is not the reserve of a registered asset. Written by
    ///        `addAsset` and cleared by `removeAsset`; the lookup is single-valued because
    ///        a reserve token belongs to at most one registered asset.
    /// @param backingVault The backing vault, or the zero address when none is designated.
    struct Registry {
        mapping(address vault => IYieldRepurchaseFacilityV2.ReserveAsset config) configs;
        address[] vaults;
        mapping(address reserve => address vault) reserveVaults;
        address backingVault;
    }

    /// @notice The registration inputs of `addAsset`.
    /// @param vault The ERC4626 vault to register.
    /// @param yieldBuybackShare The share of the yield routed to buybacks (`1e18` =
    ///        100%).
    /// @param initialReserveBalance The initial `lastReserveBalance` snapshot, in
    ///        reserve units.
    /// @param initialConversionRate The initial `lastConversionRate` snapshot: the
    ///        reserve amount redeemable for one whole share.
    /// @param nextYield The initial stored next yield, in reserve units.
    /// @param sellShares Whether bond markets pay out the vault shares instead of the
    ///        reserve.
    /// @param setAsBackingVault Whether the vault becomes the backing vault.
    struct AddAssetParams {
        address vault;
        uint256 yieldBuybackShare;
        uint256 initialReserveBalance;
        uint256 initialConversionRate;
        uint256 nextYield;
        bool sellShares;
        bool setAsBackingVault;
    }

    /// @notice Validates and registers an ERC4626 vault as a reserve asset of the
    ///         calling facility, optionally designating it as the backing vault.
    /// @dev The asset is registered in the enabled state and recorded in the
    ///      reserve-to-vault lookup. The share token is the token returned by `share()`
    ///      for a vault that advertises ERC7575 through ERC165, and the vault itself
    ///      otherwise; it is stored with the asset and never re-read. The `asyncRedeem`
    ///      flag records whether the vault advertises asynchronous redemption (ERC7540).
    ///      The registration path only designates the first backing vault; an existing
    ///      designation is replaced only through `setBackingVault`. Emits `AssetAdded`
    ///      and `NextYieldSet` for the facility, and `BackingVaultSet` when the vault is
    ///      designated.
    ///
    ///      Reverts if:
    ///      - The vault address is the zero address.
    ///      - The yield buyback share exceeds 100% (`1e18`).
    ///      - The vault is already registered.
    ///      - The vault reports the zero address as its underlying asset.
    ///      - The vault's underlying asset decimals exceed 18.
    ///      - The vault advertises asynchronous deposits (`IERC7540Deposit`) through
    ///        ERC165.
    ///      - The vault advertises asynchronous redemption (`IERC7540Redeem`) through
    ///        ERC165 without advertising ERC7575, or while `sellShares` is unset.
    ///      - The vault advertises ERC7575 through ERC165 and reports the zero address
    ///        as its `share()`.
    ///      - The share token decimals do not match the reserve decimals.
    ///      - The vault, its share token, or its reserve token is OHM, the vault or the
    ///        share token equals the reserve, or any of the three collides with the
    ///        vault, the share token, or the reserve of a registered asset.
    ///      - A probe of the vault with one whole share or one whole reserve unit
    ///        (`previewRedeem`, `previewWithdraw`, and `previewDeposit`; for a vault with
    ///        asynchronous redemption `convertToAssets`, `convertToShares`, and
    ///        `previewDeposit`) reverts, returns less than one word, or returns zero.
    ///      - The `PRICE.getPriceIn(OHM, reserve)` probe reverts or returns zero.
    ///      - `setAsBackingVault` is set together with `sellShares`.
    ///      - `setAsBackingVault` is set while a backing vault is already designated.
    /// @param registry_ The facility's asset registry storage.
    /// @param context_ The dependencies of the facility: the PRICE module is used for the
    ///        reserve price probe and the OHM token for the pool conflict checks.
    /// @param params_ The registration inputs.
    function addAsset(
        Registry storage registry_,
        IYieldRepurchaseFacilityV2.Context memory context_,
        AddAssetParams memory params_
    ) external {
        address vault_ = params_.vault;
        if (vault_ == address(0)) revert Errors.BadInput("vault");
        if (params_.yieldBuybackShare > YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh();
        if (registry_.configs[vault_].vault != address(0))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetAlreadyRegistered();

        address reserve_ = IERC4626(vault_).asset();
        if (reserve_ == address(0)) revert Errors.BadInput("vault.asset");

        uint8 reserveDecimals = IERC20Metadata(reserve_).decimals();
        if (reserveDecimals > YieldRepurchaseFacilityV2Constants.MAX_RESERVE_DECIMALS)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_UnsupportedDecimals();

        (address shareToken_, bool asyncRedeem_) = _resolveVaultClass(vault_, params_.sellShares);

        // The conversion rate probe and the sell-shares market pricing both treat
        // `10 ** reserveDecimals` as one whole share.
        if (IERC20Metadata(shareToken_).decimals() != reserveDecimals)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_VaultDecimalsMismatch();

        _requireNoPoolConflict(registry_, context_.ohm, vault_, shareToken_, reserve_);

        // The share decimals equal the reserve decimals, so one unit is both one whole
        // share and one whole reserve token.
        _probeVaultConversions(
            vault_,
            YieldRepurchaseFacilityV2Constants.DECIMAL_BASE ** reserveDecimals,
            asyncRedeem_
        );

        // The daily cycles price the vault's markets through `PRICE.getPriceIn`, so the
        // reserve must resolve against OHM at registration; a PRICE revert (for example
        // an unregistered reserve) bubbles up.
        if (PRICEv2(context_.price).getPriceIn(context_.ohm, reserve_) == 0)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_ReserveNotPriceable(
                reserve_
            );

        registry_.configs[vault_] = IYieldRepurchaseFacilityV2.ReserveAsset({
            vault: vault_,
            shareToken: shareToken_,
            reserve: reserve_,
            reserveDecimals: reserveDecimals,
            sellShares: params_.sellShares,
            isAssetEnabled: true,
            asyncRedeem: asyncRedeem_,
            yieldBuybackShare: params_.yieldBuybackShare,
            lastReserveBalance: params_.initialReserveBalance,
            lastConversionRate: params_.initialConversionRate,
            nextYield: params_.nextYield,
            unfundedYield: 0
        });
        registry_.vaults.push(vault_);
        registry_.reserveVaults[reserve_] = vault_;

        emit IYieldRepurchaseFacilityV2.AssetAdded(
            vault_,
            reserve_,
            shareToken_,
            params_.yieldBuybackShare,
            params_.sellShares,
            asyncRedeem_
        );
        emit IYieldRepurchaseFacilityV2.NextYieldSet(reserve_, params_.nextYield);

        if (params_.setAsBackingVault) {
            if (registry_.backingVault != address(0))
                revert IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_BackingVaultAlreadySet();
            _designateBackingVault(registry_, vault_, registry_.configs[vault_]);
        }
    }

    /// @notice De-registers a vault: removes it from the vault list and deletes its
    ///         reserve lookup and configuration.
    /// @dev The caller validates the removal (a registered, disabled vault that is not
    ///      the backing vault) and returns the vault's balances to the treasury before
    ///      the configuration is deleted. Emits `AssetRemoved` for the facility.
    /// @param registry_ The facility's asset registry storage.
    /// @param vault_ The vault to de-register.
    function remove(Registry storage registry_, address vault_) external {
        address[] storage vaults_ = registry_.vaults;
        uint256 vaultsLength = vaults_.length;
        for (uint256 i; i < vaultsLength; ++i) {
            if (vaults_[i] == vault_) {
                vaults_[i] = vaults_[vaultsLength - 1];
                vaults_.pop();
                break;
            }
        }

        delete registry_.reserveVaults[registry_.configs[vault_].reserve];
        delete registry_.configs[vault_];

        emit IYieldRepurchaseFacilityV2.AssetRemoved(vault_);
    }

    /// @notice Validates a change of the sell-shares mode of a registered vault.
    /// @dev Reverts if:
    ///      - The vault is not registered (`IYieldRepurchaseFacilityV2_AssetNotRegistered`).
    ///      - The stored mode already equals `sellShares_`
    ///        (`IYieldRepurchaseFacilityV2_SellSharesUnchanged`).
    ///      - `sellShares_` is set while the vault is the backing vault
    ///        (`IYieldRepurchaseFacilityV2_VaultIsBackingVault`).
    ///      - `sellShares_` is unset while the asset is flagged `asyncRedeem`
    ///        (`IYieldRepurchaseFacilityV2_AsyncRedeemRequiresSellShares`): the reserve
    ///        mode redeems the held shares synchronously.
    /// @param registry_ The facility's asset registry storage.
    /// @param vault_ The registered vault.
    /// @param sellShares_ The proposed mode.
    function validateSellShares(
        Registry storage registry_,
        address vault_,
        bool sellShares_
    ) external view {
        IYieldRepurchaseFacilityV2.ReserveAsset storage config = _requireRegistered(
            registry_,
            vault_
        );
        if (config.sellShares == sellShares_)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_SellSharesUnchanged();
        if (sellShares_) {
            if (vault_ == registry_.backingVault)
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_VaultIsBackingVault();
        } else if (config.asyncRedeem)
            revert IYieldRepurchaseFacilityV2
                .IYieldRepurchaseFacilityV2_AsyncRedeemRequiresSellShares();
    }

    /// @notice Re-reads the asynchronous-redemption flag of a registered vault from the
    ///         vault's ERC165 advertisement of `IERC7540Redeem`.
    /// @dev A vault that does not implement ERC165 reads as synchronous. The share
    ///      token is not re-read. Emits `AsyncRedeemSet` for the facility.
    ///
    ///      Reverts if:
    ///      - The vault is not registered (`IYieldRepurchaseFacilityV2_AssetNotRegistered`).
    ///      - The mode the vault advertises equals the stored flag
    ///        (`IYieldRepurchaseFacilityV2_AsyncRedeemUnchanged`).
    ///      - The vault advertises asynchronous redemption while the asset does not sell
    ///        shares (`IYieldRepurchaseFacilityV2_AsyncRedeemRequiresSellShares`).
    /// @param registry_ The facility's asset registry storage.
    /// @param vault_ The registered vault.
    function refreshAsyncRedeem(Registry storage registry_, address vault_) external {
        IYieldRepurchaseFacilityV2.ReserveAsset storage config = _requireRegistered(
            registry_,
            vault_
        );

        bool asyncRedeem = YieldRepurchaseFacilityV2VaultLib.isAsyncRedeem(vault_);
        if (asyncRedeem == config.asyncRedeem)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AsyncRedeemUnchanged();
        if (asyncRedeem && !config.sellShares)
            revert IYieldRepurchaseFacilityV2
                .IYieldRepurchaseFacilityV2_AsyncRedeemRequiresSellShares();

        config.asyncRedeem = asyncRedeem;
        emit IYieldRepurchaseFacilityV2.AsyncRedeemSet(vault_, asyncRedeem);
    }

    /// @notice Designates a registered vault as the backing vault.
    /// @dev Emits `BackingVaultSet` for the facility.
    ///
    ///      Reverts if:
    ///      - The vault is not registered (`IYieldRepurchaseFacilityV2_AssetNotRegistered`).
    ///      - The asset is disabled (`IYieldRepurchaseFacilityV2_AssetDisabled`).
    ///      - The asset sells vault shares
    ///        (`IYieldRepurchaseFacilityV2_BackingVaultCannotSellShares`).
    /// @param registry_ The facility's asset registry storage.
    /// @param vault_ The vault to designate.
    function setBackingVault(Registry storage registry_, address vault_) external {
        _designateBackingVault(registry_, vault_, _requireRegistered(registry_, vault_));
    }

    /// @notice Returns the amount of `token_` the facility can rescue to the treasury.
    /// @dev Only the OHM excess above the purchased accumulator and the full balance of
    ///      unregistered tokens are rescuable; the share and reserve tokens of the
    ///      registered assets are their buyback pools and are rejected, together with
    ///      the vault addresses.
    ///
    ///      Reverts if `token_` is the vault, the share token, or the reserve token of
    ///      a registered asset.
    /// @param registry_ The facility's asset registry storage.
    /// @param token_ The token to rescue.
    /// @param ohm_ The OHM token address.
    /// @param ohmPurchased_ The purchased-OHM accumulator backing the burn accounting.
    /// @return rescuable The rescuable amount.
    function rescuableAmount(
        Registry storage registry_,
        address token_,
        address ohm_,
        uint256 ohmPurchased_
    ) external view returns (uint256 rescuable) {
        uint256 balance = IERC20(token_).balanceOf(address(this));
        if (token_ == ohm_) {
            // The purchased OHM backs the burn accounting and must stay on the facility
            return balance > ohmPurchased_ ? balance - ohmPurchased_ : 0;
        }

        address[] storage vaults_ = registry_.vaults;
        uint256 vaultsLength = vaults_.length;
        // A token of a registered asset must reject the rescue
        // forge-lint: disable-start(require-revert-in-loop)
        for (uint256 i; i < vaultsLength; ++i) {
            if (_isPoolToken(registry_.configs[vaults_[i]], token_))
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TokenNotRescuable(
                    token_
                );
        }
        // forge-lint: disable-end(require-revert-in-loop)
        return balance;
    }

    /// @notice Recognizes the class of a vault through ERC165 and resolves its share
    ///         token.
    /// @dev ERC165 is consulted only to recognize a vault class: an ERC4626 vault is
    ///      not required to implement it, and a vault that does not is its own share
    ///      token with synchronous redemption. An ERC7575 vault names its share token
    ///      through `share()`, and the token may live in a separate contract.
    ///
    ///      Reverts if:
    ///      - The vault advertises asynchronous deposits (`IERC7540Deposit`): the idle
    ///        reserve of a sell-shares asset is wrapped through `previewDeposit` and
    ///        `deposit`, which such a vault does not serve.
    ///      - The vault advertises asynchronous redemption (`IERC7540Redeem`) without
    ///        ERC7575, which ERC7540 requires for the discovery of the share token.
    ///      - The vault advertises asynchronous redemption while `sellShares_` is unset:
    ///        the reserve mode redeems the held shares synchronously.
    ///      - The vault advertises ERC7575 and reports the zero address as its
    ///        `share()`.
    /// @return shareToken_ The ERC20 token representing the vault shares.
    /// @return asyncRedeem_ Whether the vault advertises asynchronous redemption.
    function _resolveVaultClass(
        address vault_,
        bool sellShares_
    ) private view returns (address shareToken_, bool asyncRedeem_) {
        if (ERC165Checker.supportsInterface(vault_, type(IERC7540Deposit).interfaceId))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InvalidVaultCapabilities(
                vault_
            );

        bool supportsERC7575 = ERC165Checker.supportsInterface(vault_, _ERC7575_VAULT_INTERFACE_ID);

        asyncRedeem_ = YieldRepurchaseFacilityV2VaultLib.isAsyncRedeem(vault_);
        if (asyncRedeem_) {
            if (!supportsERC7575)
                revert IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_InvalidVaultCapabilities(vault_);
            if (!sellShares_)
                revert IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_AsyncRedeemRequiresSellShares();
        }

        shareToken_ = vault_;
        if (supportsERC7575) {
            shareToken_ = IERC7575(vault_).share();
            if (shareToken_ == address(0)) revert Errors.BadInput("vault.share");
        }
    }

    /// @notice Reverts when a token of the asset being registered already belongs to a
    ///         balance pool.
    /// @dev Every token balance held by the facility belongs to exactly one pool: the OHM
    ///      balance backs the purchased-OHM counter, and the share token and reserve
    ///      balances of each registered asset back that asset. The vault address is
    ///      reserved together with them, so any collision between the three addresses of
    ///      the asset, OHM, and the addresses of the registered assets is rejected. Vaults
    ///      that share one share token therefore cannot be registered together.
    ///
    ///      Reverts with `IYieldRepurchaseFacilityV2_TokenPoolConflict` if:
    ///      - The vault, the share token, or the reserve is OHM.
    ///      - The vault or the share token equals the reserve.
    ///      - The reserve, the share token, or the vault is the vault, the share token,
    ///        or the reserve of a registered asset.
    function _requireNoPoolConflict(
        Registry storage registry_,
        address ohm_,
        address vault_,
        address shareToken_,
        address reserve_
    ) private view {
        if (vault_ == ohm_ || shareToken_ == ohm_ || reserve_ == ohm_)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TokenPoolConflict(ohm_);
        if (vault_ == reserve_ || shareToken_ == reserve_)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TokenPoolConflict(
                reserve_
            );

        address[] storage vaults_ = registry_.vaults;
        uint256 vaultsLength = vaults_.length;
        // A pool collision with any registered asset must reject the registration
        // forge-lint: disable-start(require-revert-in-loop)
        for (uint256 i; i < vaultsLength; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset storage registered = registry_.configs[
                vaults_[i]
            ];
            if (_isPoolToken(registered, reserve_))
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TokenPoolConflict(
                    reserve_
                );
            if (_isPoolToken(registered, shareToken_))
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TokenPoolConflict(
                    shareToken_
                );
            if (_isPoolToken(registered, vault_))
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_TokenPoolConflict(
                    vault_
                );
        }
        // forge-lint: disable-end(require-revert-in-loop)
    }

    /// @notice Probes the conversion functions the facility calls on a vault of the given
    ///         redemption class, so an address that does not serve them is rejected at
    ///         registration.
    /// @dev A synchronous vault is valued through `previewRedeem` and its withdrawals are
    ///      sized through `previewWithdraw`; a vault with asynchronous redemption reverts
    ///      on both, and is valued through `convertToAssets` and `convertToShares`. The
    ///      idle reserve is wrapped through `previewDeposit` for either class.
    ///
    ///      Reverts if a probe fails or returns zero (see `_probeVault`).
    /// @param vault_ The vault to probe.
    /// @param oneUnit_ One whole share, which is also one whole reserve unit.
    /// @param asyncRedeem_ Whether the vault advertises asynchronous redemption.
    function _probeVaultConversions(
        address vault_,
        uint256 oneUnit_,
        bool asyncRedeem_
    ) private view {
        if (asyncRedeem_) {
            _probeVault(vault_, IERC4626.convertToAssets.selector, oneUnit_);
            _probeVault(vault_, IERC4626.convertToShares.selector, oneUnit_);
        } else {
            _probeVault(vault_, IERC4626.previewRedeem.selector, oneUnit_);
            _probeVault(vault_, IERC4626.previewWithdraw.selector, oneUnit_);
        }
        _probeVault(vault_, IERC4626.previewDeposit.selector, oneUnit_);
    }

    /// @notice Probes a conversion function of a vault with a single amount argument.
    /// @dev The call is static and its returndata capture is capped at one word, so a
    ///      probed address cannot inflate the memory cost of the registration.
    ///
    ///      Reverts if:
    ///      - The call reverts, the address holds no code, or the returned data is
    ///        shorter than one word (`IYieldRepurchaseFacilityV2_VaultProbeFailed`).
    ///      - The returned value is zero
    ///        (`IYieldRepurchaseFacilityV2_VaultProbeZeroResult`).
    function _probeVault(address vault_, bytes4 selector_, uint256 amount_) private view {
        (bool success, bytes memory data) = SafeCall.safeStaticCall(
            vault_,
            gasleft(),
            _PROBE_RETURN_LENGTH,
            abi.encodeWithSelector(selector_, amount_)
        );
        if (!success || data.length < _PROBE_RETURN_LENGTH)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_VaultProbeFailed(
                vault_,
                selector_
            );
        if (abi.decode(data, (uint256)) == 0)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_VaultProbeZeroResult(
                vault_,
                selector_
            );
    }

    /// @notice Makes a registered vault the backing vault.
    /// @dev Reverts if:
    ///      - The asset is disabled.
    ///      - The asset sells vault shares.
    function _designateBackingVault(
        Registry storage registry_,
        address vault_,
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_
    ) private {
        if (!config_.isAssetEnabled)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetDisabled();
        if (config_.sellShares)
            revert IYieldRepurchaseFacilityV2
                .IYieldRepurchaseFacilityV2_BackingVaultCannotSellShares();

        registry_.backingVault = vault_;
        emit IYieldRepurchaseFacilityV2.BackingVaultSet(vault_);
    }

    /// @notice Returns the config of a registered vault, reverting with
    ///         `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an unregistered one.
    function _requireRegistered(
        Registry storage registry_,
        address vault_
    ) private view returns (IYieldRepurchaseFacilityV2.ReserveAsset storage config_) {
        config_ = registry_.configs[vault_];
        if (config_.vault == address(0))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered(vault_);
    }

    /// @notice Returns whether `token_` is the vault, the share token, or the reserve
    ///         token of a registered asset.
    function _isPoolToken(
        IYieldRepurchaseFacilityV2.ReserveAsset storage asset_,
        address token_
    ) private view returns (bool) {
        return token_ == asset_.vault || token_ == asset_.shareToken || token_ == asset_.reserve;
    }
}
