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
import {YRFVaultLib} from "src/policies/YieldRepurchaseFacility/YRFVaultLib.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";

// Modules
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";

/// @title YRFAssetConfigLib
/// @notice An external library that validates and maintains the per-asset registry and
///         the yield snapshots of the YieldRepurchaseFacilityV2.
/// @dev The library is deployed separately and reached through `DELEGATECALL`, so the
///      storage parameters reference the calling facility's storage, the facility is
///      `address(this)`, and the emitted events and the errors belong to the facility
///      interface.
library YRFAssetConfigLib {
    /// @notice Byte length of the single word a vault probe must return.
    uint16 private constant _PROBE_RETURN_LENGTH = 32;

    /// @notice The ERC165 identifier of an ERC7575 vault (`0x2f0a18c5`): the ERC4626
    ///         vault functions combined with `share()`.
    bytes4 private constant _ERC7575_VAULT_INTERFACE_ID =
        type(IERC4626).interfaceId ^ type(IERC7575).interfaceId;

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
    struct AddAssetParams {
        address vault;
        uint256 yieldBuybackShare;
        uint256 initialReserveBalance;
        uint256 initialConversionRate;
        uint256 nextYield;
        bool sellShares;
    }

    /// @notice Validates and registers an ERC4626 vault as a reserve asset of the
    ///         calling facility.
    /// @dev The asset is registered in the enabled state and recorded in the
    ///      reserve-to-vault lookup. The share token is the token returned by `share()`
    ///      for a vault that advertises ERC7575 through ERC165, and the vault itself
    ///      otherwise; it is stored with the asset and never re-read. The `asyncRedeem`
    ///      flag records whether the vault advertises asynchronous redemption (ERC7540).
    ///      Emits `AssetAdded` and `NextYieldSet` for the facility.
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
    ///      - The `price_.getPriceIn(ohm_, reserve)` probe reverts or returns zero.
    /// @param assetConfigs_ The facility's per-vault configuration storage.
    /// @param vaults_ The facility's registered vault list storage.
    /// @param reserveVaults_ The facility's reserve-to-vault lookup storage.
    /// @param price_ The PRICE module used for the reserve price probe.
    /// @param ohm_ The OHM token address.
    /// @param params_ The registration inputs.
    function addAsset(
        mapping(address => IYieldRepurchaseFacilityV2.ReserveAsset) storage assetConfigs_,
        address[] storage vaults_,
        mapping(address => address) storage reserveVaults_,
        PRICEv2 price_,
        address ohm_,
        AddAssetParams memory params_
    ) external {
        address vault_ = params_.vault;
        if (vault_ == address(0)) revert Errors.BadInput("vault");
        if (params_.yieldBuybackShare > YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh();
        if (assetConfigs_[vault_].vault != address(0))
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

        _requireNoPoolConflict(assetConfigs_, vaults_, ohm_, vault_, shareToken_, reserve_);

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
        if (price_.getPriceIn(ohm_, reserve_) == 0)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_ReserveNotPriceable(
                reserve_
            );

        assetConfigs_[vault_] = IYieldRepurchaseFacilityV2.ReserveAsset({
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
        vaults_.push(vault_);
        reserveVaults_[reserve_] = vault_;

        emit IYieldRepurchaseFacilityV2.AssetAdded(
            vault_,
            reserve_,
            shareToken_,
            params_.yieldBuybackShare,
            params_.sellShares,
            asyncRedeem_
        );
        emit IYieldRepurchaseFacilityV2.NextYieldSet(reserve_, params_.nextYield);
    }

    /// @notice Restarts the weekly cycle of the enabled assets: zeroes their yields and
    ///         unfunded carries, applies the supplied next-yield seeds, and refreshes
    ///         their yield snapshots.
    /// @dev Disabled assets are not touched and are not seedable. A single
    ///      `NextYieldSet` event with the resulting value is emitted per enabled vault;
    ///      when the seed array contains duplicates, the last entry wins. The epoch
    ///      counter and the seeding window of the facility are not written here.
    ///
    ///      Reverts if a seed references an unregistered or disabled vault.
    /// @param assetConfigs_ The facility's per-vault configuration storage.
    /// @param vaults_ The facility's registered vault list storage.
    /// @param nextYieldSeeds_ The per-vault `nextYield` values to apply after the reset.
    /// @param chreg_ The Clearinghouse registry module, read for the balance snapshots.
    /// @param trsry_ The treasury address, read for the balance snapshots.
    /// @param backingVault_ The backing vault, or the zero address when none is
    ///        designated.
    function resetCycle(
        mapping(address => IYieldRepurchaseFacilityV2.ReserveAsset) storage assetConfigs_,
        address[] storage vaults_,
        IYieldRepurchaseFacilityV2.NextYieldSeed[] memory nextYieldSeeds_,
        CHREGv1 chreg_,
        address trsry_,
        address backingVault_
    ) external {
        uint256 vaultsLength = vaults_.length;
        for (uint256 i = 0; i < vaultsLength; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset storage config = assetConfigs_[vaults_[i]];
            if (!config.isAssetEnabled) continue;

            config.nextYield = 0;
            config.unfundedYield = 0;
            _refreshSnapshots(config, chreg_, trsry_, backingVault_);
        }

        uint256 seedsLength = nextYieldSeeds_.length;
        // An unregistered or disabled seed must reject the whole reset rather than be skipped
        // forge-lint: disable-start(require-revert-in-loop)
        for (uint256 i = 0; i < seedsLength; ++i) {
            IYieldRepurchaseFacilityV2.NextYieldSeed memory seed = nextYieldSeeds_[i];
            IYieldRepurchaseFacilityV2.ReserveAsset storage config = assetConfigs_[seed.vault];
            if (config.vault == address(0))
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered(
                    seed.vault
                );
            if (!config.isAssetEnabled)
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetDisabled();
            config.nextYield = seed.nextYield;
        }
        // forge-lint: disable-end(require-revert-in-loop)

        for (uint256 i = 0; i < vaultsLength; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset storage config = assetConfigs_[vaults_[i]];
            if (!config.isAssetEnabled) continue;
            emit IYieldRepurchaseFacilityV2.NextYieldSet(config.reserve, config.nextYield);
        }
    }

    /// @notice Refreshes the vault's conversion-rate and reserve-balance snapshots.
    /// @param config_ The vault's configuration storage.
    /// @param chreg_ The Clearinghouse registry module.
    /// @param trsry_ The treasury address.
    /// @param backingVault_ The backing vault, or the zero address when none is
    ///        designated.
    function refreshSnapshots(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        CHREGv1 chreg_,
        address trsry_,
        address backingVault_
    ) external {
        _refreshSnapshots(config_, chreg_, trsry_, backingVault_);
    }

    /// @notice Returns the reserve value of the protocol-held shares of a vault.
    /// @dev Counts the treasury balance of the share token, and for the backing vault
    ///      also the balances of the active Clearinghouses, valued by the redemption
    ///      class of the vault (`YRFVaultLib.sharesToAssets`, floor).
    /// @param config_ The configuration storage of the vault to value.
    /// @param chreg_ The Clearinghouse registry module.
    /// @param trsry_ The treasury address.
    /// @param backingVault_ The backing vault, or the zero address when none is
    ///        designated.
    /// @return balance The reserve value, in reserve units.
    function protocolReserveBalance(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        CHREGv1 chreg_,
        address trsry_,
        address backingVault_
    ) external view returns (uint256 balance) {
        return _protocolReserveBalance(config_, chreg_, trsry_, backingVault_);
    }

    /// @notice Returns the amount of `token_` the facility can rescue to the treasury.
    /// @dev Only the OHM excess above the purchased accumulator and the full balance of
    ///      unregistered tokens are rescuable; the share and reserve tokens of the
    ///      registered assets are their buyback pools and are rejected, together with
    ///      the vault addresses.
    ///
    ///      Reverts if `token_` is the vault, the share token, or the reserve token of
    ///      a registered asset.
    /// @param assetConfigs_ The facility's per-vault configuration storage.
    /// @param vaults_ The facility's registered vault list storage.
    /// @param token_ The token to rescue.
    /// @param ohm_ The OHM token address.
    /// @param ohmPurchased_ The purchased-OHM accumulator backing the burn accounting.
    /// @return rescuable The rescuable amount.
    function rescuableAmount(
        mapping(address => IYieldRepurchaseFacilityV2.ReserveAsset) storage assetConfigs_,
        address[] storage vaults_,
        address token_,
        address ohm_,
        uint256 ohmPurchased_
    ) external view returns (uint256 rescuable) {
        uint256 balance = IERC20(token_).balanceOf(address(this));
        if (token_ == ohm_) {
            // The purchased OHM backs the burn accounting and must stay on the facility
            return balance > ohmPurchased_ ? balance - ohmPurchased_ : 0;
        }

        uint256 vaultsLength = vaults_.length;
        // A token of a registered asset must reject the rescue
        // forge-lint: disable-start(require-revert-in-loop)
        for (uint256 i = 0; i < vaultsLength; ++i) {
            if (_isPoolToken(assetConfigs_[vaults_[i]], token_))
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

        asyncRedeem_ = YRFVaultLib.isAsyncRedeem(vault_);
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
        mapping(address => IYieldRepurchaseFacilityV2.ReserveAsset) storage assetConfigs_,
        address[] storage vaults_,
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

        uint256 vaultsLength = vaults_.length;
        // A pool collision with any registered asset must reject the registration
        // forge-lint: disable-start(require-revert-in-loop)
        for (uint256 i = 0; i < vaultsLength; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset storage registered = assetConfigs_[vaults_[i]];
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

    // The loops here and in `resetCycle` run over the registered vaults, added only by the
    // configurator, and the active Clearinghouses, activated only through the permissioned
    // CHREG module.
    // forge-lint: disable-start(calls-loop)
    /// @notice Refreshes the snapshots of a vault configuration in place.
    function _refreshSnapshots(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        CHREGv1 chreg_,
        address trsry_,
        address backingVault_
    ) private {
        // One whole share: `addAsset` requires the share decimals to equal the reserve
        // decimals
        config_.lastConversionRate = YRFVaultLib.sharesToAssets(
            config_,
            10 ** config_.reserveDecimals
        );
        config_.lastReserveBalance = _protocolReserveBalance(
            config_,
            chreg_,
            trsry_,
            backingVault_
        );
    }

    /// @notice Returns the reserve value of the protocol-held shares of a vault.
    function _protocolReserveBalance(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        CHREGv1 chreg_,
        address trsry_,
        address backingVault_
    ) private view returns (uint256 balance) {
        address vault_ = config_.vault;
        IERC20 shareToken = IERC20(config_.shareToken);
        uint256 totalShares = shareToken.balanceOf(trsry_);

        if (vault_ == backingVault_) {
            uint256 activeCount = chreg_.activeCount();
            for (uint256 i = 0; i < activeCount; ++i) {
                totalShares += shareToken.balanceOf(chreg_.active(i));
            }
        }

        balance = YRFVaultLib.sharesToAssets(config_, totalShares);
    }

    // forge-lint: disable-end(calls-loop)

    /// @notice Returns whether `token_` is the vault, the share token, or the reserve
    ///         token of a registered asset.
    function _isPoolToken(
        IYieldRepurchaseFacilityV2.ReserveAsset storage asset_,
        address token_
    ) private view returns (bool) {
        return token_ == asset_.vault || token_ == asset_.shareToken || token_ == asset_.reserve;
    }
}
