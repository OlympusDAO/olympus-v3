// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {YieldRepurchaseFacilityV2AssetRegistryLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2AssetRegistryLib.sol";
import {YieldRepurchaseFacilityV2MathLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2MathLib.sol";
import {YieldRepurchaseFacilityV2ValidationLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2ValidationLib.sol";
import {YieldRepurchaseFacilityV2VaultLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2VaultLib.sol";

// Modules
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";

/// @title YieldRepurchaseFacilityV2YieldLib
/// @notice An external library that owns the yield accounting of the registered assets of
///         the YieldRepurchaseFacilityV2: the yield projection, the conversion-rate and
///         reserve-balance snapshots, the stored next yield, and the unfunded carry; it
///         also enables a disabled asset, since the enable resets that accounting.
/// @dev The library is deployed separately and reached through `DELEGATECALL`, so the
///      storage parameters reference the calling facility's storage and the emitted
///      events belong to the facility interface. The treasury withdrawal of the weekly
///      reset stays with the facility: the reset of a vault is split into
///      `beginWeeklyReset`, which projects and returns the funding target, and
///      `finishWeeklyReset`, which records the funded value and the balance snapshot.
///      Nothing here reads the facility's balances. The arithmetic is that of
///      `YieldRepurchaseFacilityV2MathLib`, and the share valuation that of
///      `YieldRepurchaseFacilityV2VaultLib`, which the lens shares.
library YieldRepurchaseFacilityV2YieldLib {
    /// @notice Restarts the weekly cycle of the enabled assets: zeroes their yields and
    ///         unfunded carries, applies the supplied next-yield seeds, and refreshes
    ///         their yield snapshots.
    /// @dev Disabled assets are not touched and are not seedable. A single
    ///      `NextYieldSet` event with the resulting value is emitted per enabled vault;
    ///      when the seed array contains duplicates, the last entry wins. The epoch
    ///      counter and the seeding window of the facility are not written here.
    ///
    ///      Reverts if a seed references an unregistered or disabled vault.
    /// @param registry_ The facility's asset registry storage.
    /// @param nextYieldSeeds_ The per-vault `nextYield` values to apply after the reset.
    /// @param context_ The dependencies of the facility, read for the balance snapshots.
    function restart(
        YieldRepurchaseFacilityV2AssetRegistryLib.Registry storage registry_,
        IYieldRepurchaseFacilityV2.NextYieldSeed[] memory nextYieldSeeds_,
        IYieldRepurchaseFacilityV2.Context memory context_
    ) external {
        address[] storage vaults_ = registry_.vaults;
        uint256 vaultsLength = vaults_.length;
        for (uint256 i; i < vaultsLength; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset storage config = registry_.configs[vaults_[i]];
            if (!config.isAssetEnabled) continue;

            config.nextYield = 0;
            config.unfundedYield = 0;
            _refreshSnapshots(config, context_);
        }

        uint256 seedsLength = nextYieldSeeds_.length;
        // An unregistered or disabled seed must reject the whole reset rather than be skipped
        // forge-lint: disable-start(require-revert-in-loop)
        for (uint256 i; i < seedsLength; ++i) {
            IYieldRepurchaseFacilityV2.NextYieldSeed memory seed = nextYieldSeeds_[i];
            IYieldRepurchaseFacilityV2.ReserveAsset storage config = registry_.configs[seed.vault];
            if (config.vault == address(0))
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered(
                    seed.vault
                );
            if (!config.isAssetEnabled)
                revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetDisabled();
            config.nextYield = seed.nextYield;
        }
        // forge-lint: disable-end(require-revert-in-loop)

        for (uint256 i; i < vaultsLength; ++i) {
            IYieldRepurchaseFacilityV2.ReserveAsset storage config = registry_.configs[vaults_[i]];
            if (!config.isAssetEnabled) continue;
            emit IYieldRepurchaseFacilityV2.NextYieldSet(config.reserve, config.nextYield);
        }
    }

    /// @notice Enables a disabled registered vault and resets its yield accounting:
    ///         zeroes the unfunded carry, refreshes the yield snapshots, and zeroes the
    ///         stored next yield.
    /// @dev Emits `AssetEnabled` and then `NextYieldSet` for the facility. Nothing here
    ///      reads the facility's balances.
    ///
    ///      Reverts if:
    ///      - The vault is not registered (`IYieldRepurchaseFacilityV2_AssetNotRegistered`).
    ///      - The asset is enabled (`IYieldRepurchaseFacilityV2_AssetEnabled`).
    /// @param registry_ The facility's asset registry storage.
    /// @param vault_ The vault to enable.
    /// @param context_ The dependencies of the facility, read for the balance snapshot.
    function enableAsset(
        YieldRepurchaseFacilityV2AssetRegistryLib.Registry storage registry_,
        address vault_,
        IYieldRepurchaseFacilityV2.Context memory context_
    ) external {
        IYieldRepurchaseFacilityV2.ReserveAsset storage config = _requireRegistered(
            registry_,
            vault_
        );
        YieldRepurchaseFacilityV2ValidationLib.requireAssetDisabled(config.isAssetEnabled);

        config.isAssetEnabled = true;
        emit IYieldRepurchaseFacilityV2.AssetEnabled(vault_);

        config.unfundedYield = 0;
        _refreshSnapshots(config, context_);
        _setNextYield(config, 0);
    }

    /// @notice Lowers the stored next yield of a registered vault.
    /// @dev The stored value must equal `expectedNextYield_` and `newNextYield_` must be
    ///      lower than it (`YieldRepurchaseFacilityV2ValidationLib`). Emits `NextYieldSet`
    ///      for the facility. The unfunded carry is not changed.
    ///
    ///      Reverts if:
    ///      - The vault is not registered (`IYieldRepurchaseFacilityV2_AssetNotRegistered`).
    ///      - The stored next yield does not equal `expectedNextYield_`
    ///        (`IYieldRepurchaseFacilityV2_NextYieldMismatch`).
    ///      - `newNextYield_` is not lower than the stored value
    ///        (`IYieldRepurchaseFacilityV2_NextYieldNotDecreased`).
    /// @param registry_ The facility's asset registry storage.
    /// @param vault_ The registered vault.
    /// @param expectedNextYield_ The stored next yield the correction targets, in reserve
    ///        units.
    /// @param newNextYield_ The corrected next yield, in reserve units.
    function decreaseNextYield(
        YieldRepurchaseFacilityV2AssetRegistryLib.Registry storage registry_,
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external {
        IYieldRepurchaseFacilityV2.ReserveAsset storage config = _requireRegistered(
            registry_,
            vault_
        );
        YieldRepurchaseFacilityV2ValidationLib.requireNextYieldDecrease(
            vault_,
            expectedNextYield_,
            config.nextYield,
            newNextYield_
        );

        _setNextYield(config, newNextYield_);
    }

    /// @notice Begins the weekly reset of a vault: projects the yield of the coming week
    ///         into the stored next yield, refreshes the conversion-rate snapshot, and
    ///         returns the funding target of the treasury withdrawal the facility
    ///         performs next.
    /// @dev The funding target is the stored `nextYield` plus the `unfundedYield` carried
    ///      from earlier shortfalls, read before the projection replaces the stored value;
    ///      it does not depend on the facility's balances. The projection reads the stored
    ///      snapshots against the current rate, so it runs before the rate snapshot is
    ///      refreshed. Emits `NextYieldSet` for the facility.
    /// @param config_ The vault's configuration storage.
    /// @param context_ The dependencies of the facility: the backing vault.
    /// @param clearinghouseYield_ The weekly Clearinghouse interest credited to the
    ///        backing vault, in backing reserve units.
    /// @return fundingTarget The amount to withdraw from the treasury into the buyback
    ///         pool, in reserve units.
    function beginWeeklyReset(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        IYieldRepurchaseFacilityV2.Context memory context_,
        uint256 clearinghouseYield_
    ) external returns (uint256 fundingTarget) {
        fundingTarget = config_.nextYield + config_.unfundedYield;

        // The projection reads the stored snapshots against the current rate, so it must
        // run before the snapshots are refreshed below.
        uint256 newNextYield = _projectNextYield(config_, context_, clearinghouseYield_);

        _setNextYield(config_, newNextYield);

        config_.lastConversionRate = _conversionRate(config_);
    }

    /// @notice Finishes the weekly reset of a vault after the funding withdrawal: stores
    ///         the remainder the treasury balance could not cover and refreshes the
    ///         reserve-balance snapshot.
    /// @dev The balance snapshot is taken after the funding withdrawal, so it excludes the
    ///      shares moved to the facility. The unfunded remainder is retried at the
    ///      following reset.
    /// @param config_ The vault's configuration storage.
    /// @param context_ The dependencies of the facility, read for the balance snapshot.
    /// @param fundingTarget_ The funding target returned by `beginWeeklyReset`, in
    ///        reserve units.
    /// @param funded_ The value the treasury withdrawal covered, in reserve units.
    function finishWeeklyReset(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        IYieldRepurchaseFacilityV2.Context memory context_,
        uint256 fundingTarget_,
        uint256 funded_
    ) external {
        config_.unfundedYield = YieldRepurchaseFacilityV2MathLib.unfundedRemainder(
            fundingTarget_,
            funded_
        );
        config_.lastReserveBalance = _protocolReserveBalance(config_, context_);
    }

    /// @notice Projects the next yield of a vault, in reserve units: the vault yield
    ///         accrued since the snapshots, plus the weekly Clearinghouse interest for
    ///         the backing vault, multiplied by the vault's buyback share (floor).
    /// @dev The Clearinghouse interest is credited only to the backing vault; the other
    ///      vaults pass zero to the projection.
    function _projectNextYield(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        IYieldRepurchaseFacilityV2.Context memory context_,
        uint256 clearinghouseYield_
    ) private view returns (uint256) {
        uint256 vaultYield = _computeVaultYield(config_);
        return
            YieldRepurchaseFacilityV2MathLib.projectNextYield(
                vaultYield,
                config_.vault == context_.backingVault ? clearinghouseYield_ : 0,
                config_.yieldBuybackShare
            );
    }

    /// @notice Returns the reserve value of the protocol-held shares of a vault.
    /// @dev Counts the treasury balance of the share token, and for the backing vault
    ///      also the balances of the active Clearinghouses, valued by the redemption
    ///      class of the vault (`YieldRepurchaseFacilityV2VaultLib.sharesToAssets`,
    ///      floor).
    // The loop runs over the active Clearinghouses, activated only through the permissioned
    // CHREG module.
    // forge-lint: disable-next-item(calls-loop)
    function _protocolReserveBalance(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        IYieldRepurchaseFacilityV2.Context memory context_
    ) private view returns (uint256 balance) {
        address vault_ = config_.vault;
        IERC20 shareToken = IERC20(config_.shareToken);
        uint256 totalShares = shareToken.balanceOf(context_.trsry);

        if (vault_ == context_.backingVault) {
            CHREGv1 chreg = CHREGv1(context_.chreg);
            uint256 activeCount = chreg.activeCount();
            for (uint256 i; i < activeCount; ++i) {
                totalShares += shareToken.balanceOf(chreg.active(i));
            }
        }

        balance = YieldRepurchaseFacilityV2VaultLib.sharesToAssets(
            vault_,
            config_.asyncRedeem,
            totalShares
        );
    }

    /// @notice Refreshes the conversion-rate and reserve-balance snapshots of a vault
    ///         configuration in place.
    // Reached from the `restart` loop over the registered vaults, added only by the
    // configurator.
    // forge-lint: disable-next-item(calls-loop)
    function _refreshSnapshots(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        IYieldRepurchaseFacilityV2.Context memory context_
    ) private {
        config_.lastConversionRate = _conversionRate(config_);
        config_.lastReserveBalance = _protocolReserveBalance(config_, context_);
    }

    /// @notice Returns the vault yield accrued since the snapshots, in reserve units.
    /// @dev `lastReserveBalance * (currentRate - lastRate) / lastRate`, floored
    ///      (`YieldRepurchaseFacilityV2MathLib.vaultYield`). Zero when the rate has not
    ///      increased or the rate snapshot is unset; with the snapshot unset the vault
    ///      is not read.
    ///
    ///      The basis is the balance snapshot of the last weekly reset, so balance
    ///      changes between the snapshots do not enter the yield: the rate delta is
    ///      credited on the full snapshot balance even when a part of it has left the
    ///      protocol during the week, and a balance added during the week starts
    ///      accruing only from the following snapshot, which rebases the projection to
    ///      the actual balance.
    ///
    ///      The projection assumes a rate that does not decrease. Every weekly reset
    ///      overwrites the rate snapshot with the current rate, so after a decrease of
    ///      the rate its recovery up to the earlier level is credited as yield.
    function _computeVaultYield(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_
    ) private view returns (uint256 yield) {
        uint256 lastRate = config_.lastConversionRate;
        if (lastRate == 0) return 0;

        uint256 currentRate = _conversionRate(config_);
        yield = YieldRepurchaseFacilityV2MathLib.vaultYield(
            config_.lastReserveBalance,
            lastRate,
            currentRate
        );
    }

    /// @notice Returns the vault's conversion rate: the reserve value of one whole
    ///         share (`YieldRepurchaseFacilityV2VaultLib.conversionRate`).
    function _conversionRate(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_
    ) private view returns (uint256) {
        return
            YieldRepurchaseFacilityV2VaultLib.conversionRate(
                config_.vault,
                config_.asyncRedeem,
                config_.reserveDecimals
            );
    }

    /// @notice Returns the config of a registered vault, reverting with
    ///         `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an unregistered one.
    function _requireRegistered(
        YieldRepurchaseFacilityV2AssetRegistryLib.Registry storage registry_,
        address vault_
    ) private view returns (IYieldRepurchaseFacilityV2.ReserveAsset storage config_) {
        config_ = registry_.configs[vault_];
        if (config_.vault == address(0))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered(vault_);
    }

    /// @notice Stores the vault's next yield and emits `NextYieldSet`.
    function _setNextYield(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        uint256 nextYield_
    ) private {
        config_.nextYield = nextYield_;
        emit IYieldRepurchaseFacilityV2.NextYieldSet(config_.reserve, nextYield_);
    }
}
