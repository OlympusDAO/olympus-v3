// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";
import {YieldRepurchaseFacilityV2AssetRegistryLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2AssetRegistryLib.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";
import {YieldRepurchaseFacilityV2VaultLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2VaultLib.sol";

// Modules
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";

/// @title YieldRepurchaseFacilityV2YieldLib
/// @notice An external library that owns the yield accounting of the registered assets of
///         the YieldRepurchaseFacilityV2: the yield projection, the conversion-rate and
///         reserve-balance snapshots, the stored next yield, and the unfunded carry.
/// @dev The library is deployed separately and reached through `DELEGATECALL`, so the
///      storage parameters reference the calling facility's storage and the emitted
///      events belong to the facility interface. The treasury withdrawal of the weekly
///      reset stays with the facility: the reset of a vault is split into
///      `beginWeeklyReset`, which projects and returns the funding target, and
///      `finishWeeklyReset`, which records the funded value and the balance snapshot.
///      Nothing here reads the facility's balances.
library YieldRepurchaseFacilityV2YieldLib {
    using FullMath for uint256;
    using YieldRepurchaseFacilityV2VaultLib for IYieldRepurchaseFacilityV2.ReserveAsset;

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

    /// @notice Resets the yield accounting of an asset: zeroes the unfunded carry,
    ///         refreshes the yield snapshots, and zeroes the stored next yield.
    /// @dev Emits `NextYieldSet` for the facility. Nothing here reads the facility's
    ///      balances.
    /// @param config_ The vault's configuration storage.
    /// @param context_ The dependencies of the facility, read for the balance snapshot.
    function resetAsset(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        IYieldRepurchaseFacilityV2.Context memory context_
    ) external {
        config_.unfundedYield = 0;
        _refreshSnapshots(config_, context_);
        _setNextYield(config_, 0);
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
        uint256 newNextYield = projectNextYield(config_, context_, clearinghouseYield_);

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
        config_.unfundedYield = Math.saturatingSub(fundingTarget_, funded_);
        config_.lastReserveBalance = protocolReserveBalance(config_, context_);
    }

    /// @notice Projects the next yield of a vault, in reserve units: the vault yield
    ///         accrued since the snapshots, plus the weekly Clearinghouse interest for
    ///         the backing vault, multiplied by the vault's buyback share (floor).
    /// @param config_ The vault's configuration storage.
    /// @param context_ The dependencies of the facility: the backing vault.
    /// @param clearinghouseYield_ The weekly Clearinghouse interest, in backing reserve
    ///        units; credited only to the backing vault.
    /// @return The projected yield, in reserve units.
    function projectNextYield(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        IYieldRepurchaseFacilityV2.Context memory context_,
        uint256 clearinghouseYield_
    ) public view returns (uint256) {
        uint256 vaultYield = _computeVaultYield(config_);
        uint256 totalYield = config_.vault == context_.backingVault
            ? vaultYield + clearinghouseYield_
            : vaultYield;
        return
            totalYield.mulDiv(
                config_.yieldBuybackShare,
                YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT
            );
    }

    /// @notice Returns the reserve value of the protocol-held shares of a vault.
    /// @dev Counts the treasury balance of the share token, and for the backing vault
    ///      also the balances of the active Clearinghouses, valued by the redemption
    ///      class of the vault (`YieldRepurchaseFacilityV2VaultLib.sharesToAssets`,
    ///      floor).
    /// @param config_ The configuration storage of the vault to value.
    /// @param context_ The dependencies of the facility: the treasury, the CHREG module,
    ///        and the backing vault.
    /// @return balance The reserve value, in reserve units.
    // The loop runs over the active Clearinghouses, activated only through the permissioned
    // CHREG module.
    // forge-lint: disable-next-item(calls-loop)
    function protocolReserveBalance(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_,
        IYieldRepurchaseFacilityV2.Context memory context_
    ) public view returns (uint256 balance) {
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

        balance = config_.sharesToAssets(totalShares);
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
        config_.lastReserveBalance = protocolReserveBalance(config_, context_);
    }

    /// @notice Returns the vault yield accrued since the snapshots, in reserve units.
    /// @dev `lastReserveBalance * (currentRate - lastRate) / lastRate`, floored. Zero
    ///      when the rate has not increased or the rate snapshot is unset.
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
        if (currentRate <= lastRate) return 0;

        yield = config_.lastReserveBalance.mulDiv(currentRate - lastRate, lastRate);
    }

    /// @notice Returns the vault's conversion rate: the reserve value of one whole
    ///         share.
    /// @dev The probe amount `10 ** reserveDecimals` is one whole share because `addAsset`
    ///      requires the share token decimals to equal the reserve decimals. The rate is
    ///      `previewRedeem` of that amount, or `convertToAssets` for an asset with
    ///      asynchronous redemption.
    function _conversionRate(
        IYieldRepurchaseFacilityV2.ReserveAsset storage config_
    ) private view returns (uint256) {
        return
            config_.sharesToAssets(
                YieldRepurchaseFacilityV2Constants.DECIMAL_BASE ** config_.reserveDecimals
            );
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
