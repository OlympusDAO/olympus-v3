// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Interfaces
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

/// @title IYieldRepurchaseFacilityV2View
/// @notice The read-only surface of the multi-asset Yield Repurchase Facility (YRF)
///         policy.
interface IYieldRepurchaseFacilityV2View is IYieldRepurchaseFacilityV2 {
    // ============ VALIDATION ============ //

    /// @notice Validates the parameters of `setYieldBuybackShare` against the live
    ///         facility state, reverting when the setter's value checks would fail.
    /// @dev The validation applies no authorization gate. Intended to be called by the
    ///      config timelock when a `setYieldBuybackShare` action is queued.
    /// @param vault_ The registered vault.
    /// @param newShare_ The proposed share (`1e18` = 100%).
    function validateSetYieldBuybackShare(address vault_, uint256 newShare_) external view;

    /// @notice Validates the parameter of `setInitialDiscount`, reverting when the
    ///         setter's value check would fail.
    /// @dev The validation applies no authorization gate. Intended to be called by the
    ///      config timelock when a `setInitialDiscount` action is queued.
    /// @param initialDiscount_ The proposed discount (`1e18` = 100%).
    function validateSetInitialDiscount(uint256 initialDiscount_) external view;

    /// @notice Validates the parameter of `setMaxPricePremium`, reverting when the
    ///         setter's value check would fail.
    /// @dev The validation applies no authorization gate. Intended to be called by the
    ///      config timelock when a `setMaxPricePremium` action is queued.
    /// @param maxPricePremium_ The proposed premium (`1e18` = 100%); must not exceed
    ///        `10e18`.
    function validateSetMaxPricePremium(uint256 maxPricePremium_) external view;

    /// @notice Validates the parameter of `enableAsset` against the live facility state,
    ///         reverting when the setter's value checks would fail.
    /// @dev The validation applies no authorization gate. Intended to be called by the
    ///      config timelock when an `enableAsset` action is queued.
    /// @param vault_ The vault to enable.
    function validateEnableAsset(address vault_) external view;

    /// @notice Validates the parameter of `disableAsset` against the live facility state,
    ///         reverting when the setter's value checks would fail.
    /// @dev The validation applies no authorization gate. Intended to be called by the
    ///      config timelock when a `disableAsset` action is queued.
    /// @param vault_ The vault to disable.
    function validateDisableAsset(address vault_) external view;

    /// @notice Validates the parameter of `excludeClearinghouse` against the live
    ///         facility state, reverting when the setter's value check would fail.
    /// @dev The validation applies no authorization gate. Intended to be called by the
    ///      config timelock when an `excludeClearinghouse` action is queued.
    /// @param clearinghouse_ The Clearinghouse address.
    function validateExcludeClearinghouse(address clearinghouse_) external view;

    /// @notice Validates the parameters of `increaseClearinghouseOffset` against the live
    ///         facility state, reverting when the setter's value checks would fail.
    /// @dev The validation applies no authorization gate. The receivables are read live,
    ///      so a validation that passes can be invalidated by repayments before the
    ///      setter runs. Intended to be called by the config timelock when an
    ///      `increaseClearinghouseOffset` action is queued.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @param additionalOffset_ The amount added to the existing offset, in the
    ///        receivables' units.
    function validateIncreaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external view;

    /// @notice Validates the parameters of `decreaseNextYield` against the live facility
    ///         state, reverting when the setter's value checks would fail.
    /// @dev The validation applies no authorization gate. The stored next yield is read
    ///      live, so a validation that passes can be invalidated by a weekly reset before
    ///      the setter runs. Intended to be called by the config timelock when a
    ///      `decreaseNextYield` action is queued.
    /// @param vault_ The registered vault.
    /// @param expectedNextYield_ The stored next yield the correction targets, in reserve
    ///        units.
    /// @param newNextYield_ The corrected next yield, in reserve units.
    function validateDecreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external view;

    // ============ VIEW FUNCTIONS ============ //

    /// @notice Returns the registered vaults.
    /// @dev The ordering is not meaningful: removals reorder the list.
    /// @return vaults The registered vault addresses.
    function getVaults() external view returns (address[] memory);

    /// @notice Returns the configuration and accounting of a registered vault.
    /// @dev Reverts with `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an
    ///      unregistered vault.
    /// @param vault_ The registered vault.
    /// @return config The per-vault configuration and accounting.
    function getAssetConfig(address vault_) external view returns (ReserveAsset memory config);

    /// @notice Returns the yield a weekly reset running now would project for the vault:
    ///         the vault yield accrued since the snapshots, plus the weekly Clearinghouse
    ///         interest for the backing vault, multiplied by the vault's buyback share.
    /// @dev This is a live projection; the stored next yield is available through
    ///      `getAssetConfig`. The projection applies the rate change since the last
    ///      weekly reset to the balance snapshot taken at that reset: protocol balance
    ///      changes made after the snapshot do not enter the projection until the
    ///      following reset, and a stored projection overstated by an outflow can be
    ///      lowered through `decreaseNextYield`. Reverts with
    ///      `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an unregistered vault.
    /// @param vault_ The registered vault.
    /// @return yield The projected yield, in reserve units.
    function getNextYield(address vault_) external view returns (uint256 yield);

    /// @notice Returns the reserve value of the protocol-held shares of a vault: the
    ///         treasury balance, and for the backing vault also the balances of the
    ///         active Clearinghouses.
    /// @dev Reverts with `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an
    ///      unregistered vault.
    /// @param vault_ The registered vault.
    /// @return balance The reserve value, in reserve units.
    function getReserveBalance(address vault_) external view returns (uint256 balance);

    /// @notice Returns the reserve token of the vault that funds a market created by the
    ///         facility on the current bond auctioneer.
    /// @param marketId_ The market ID.
    /// @return reserve The reserve token, or the zero address when the market was not
    ///         created by the facility on the current bond auctioneer.
    function marketReserves(uint256 marketId_) external view returns (address reserve);

    /// @notice Returns the cumulative receivables offset of a Clearinghouse.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @return The cumulative offset, in the receivables' units.
    function clearinghouseOffset(address clearinghouse_) external view returns (uint256);

    /// @notice Returns whether a Clearinghouse is included in the backing yield regardless
    ///         of its reserve token.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @return Whether the Clearinghouse is included.
    function isClearinghouseIncluded(address clearinghouse_) external view returns (bool);

    /// @notice Returns the teller trusted to invoke the bond callback.
    /// @return The teller address.
    function bondTeller() external view returns (address);

    /// @notice Returns the SDA auctioneer used to create bond markets.
    /// @return The auctioneer address.
    function bondAuctioneer() external view returns (address);

    /// @notice Returns the backing oracle providing the 18-decimal reserve-per-OHM
    ///         backing value.
    /// @return The backing oracle policy address.
    function backingOracle() external view returns (address);

    /// @notice Returns the backing vault.
    /// @return The backing vault address, or the zero address when none is designated.
    function backingVault() external view returns (address);

    /// @notice Returns the discount applied to the oracle price when a bond market opens.
    /// @return The discount (`1e18` = 100%).
    function initialDiscount() external view returns (uint256);

    /// @notice Returns the premium over the oracle price at which a bond market's
    ///         minimum price is placed, capping the reserve paid for one OHM at
    ///         `oraclePrice * (1 + maxPricePremium)`.
    /// @return The premium (`1e18` = 100%).
    function maxPricePremium() external view returns (uint256);

    /// @notice Returns the OHM purchased through the facility's bond markets and not yet
    ///         burned.
    /// @dev The facility's OHM balance always covers this amount.
    /// @return The purchased OHM amount.
    function ohmPurchased() external view returns (uint256);

    /// @notice Returns the running epoch counter, in the range `[0, 21)`.
    /// @dev The counter advances by one per heart beat while the facility is enabled;
    ///      three epochs form a day, and reaching epoch 21 runs the weekly reset before
    ///      the counter wraps to zero. A restart through `enable` sets the counter to
    ///      20, and `seedCycle` sets it to the seeded value.
    /// @return The epoch counter.
    function epoch() external view returns (uint48);

    /// @notice Returns whether the seeding window of `seedCycle` is open: the latest
    ///         `enable` restart has not been seeded yet and no heart beat has run since
    ///         the restart.
    /// @return Whether `seedCycle` is callable.
    function isCycleSeedable() external view returns (bool);

    /// @notice Returns the configurator: the configuration policy that is the only caller
    ///         of the configurator-restricted functions.
    /// @return The configurator address, or the zero address while none is set.
    function configurator() external view returns (address);

    /// @notice Returns the exclusive upper bound of the re-enable grace window, in
    ///         seconds: the window must be strictly shorter than one weekly cycle.
    /// @return The bound, in seconds.
    // solhint-disable-next-line func-name-mixedcase
    function MAX_GRACE_PERIOD() external view returns (uint32);
}
