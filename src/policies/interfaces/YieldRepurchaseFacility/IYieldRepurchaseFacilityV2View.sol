// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Interfaces
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

/// @title IYieldRepurchaseFacilityV2View
/// @notice The read-only surface of the multi-asset Yield Repurchase Facility (YRF)
///         policy: the stored configuration and accounting, and the dependencies.
/// @dev The views derived from this state and from the dependencies (the live yield
///      projection, the protocol reserve balance, the buyback pools, the vault markets,
///      the Clearinghouse breakdown, and the price gate) are provided by
///      `IYieldRepurchaseFacilityV2Lens`, and the validation of the operator setters for
///      the config timelock by `IYieldRepurchaseFacilityV2Config`, which reads this
///      surface. The facility also implements `IYieldRepurchaseRecipient`, the read-only
///      surface through which a sender of protocol yield discovers the registered vaults:
///      `getVaults` is shared with this interface, and `getVaultConfig` and
///      `getAssetVault` are declared there.
interface IYieldRepurchaseFacilityV2View is IYieldRepurchaseFacilityV2 {
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

    /// @notice Returns the vault that funds a market created by the facility on the
    ///         current bond auctioneer.
    /// @param marketId_ The market ID.
    /// @return vault The vault, or the zero address when the market was not created by
    ///         the facility on the current bond auctioneer.
    function marketVault(uint256 marketId_) external view returns (address vault);

    /// @notice Returns the tracked bond market of a vault: the only market of the vault
    ///         whose purchases the bond callback serves.
    /// @dev The tracked market is cleared whenever a close of it is attempted, and a
    ///      bond-contract change closes every tracked market, so the market belongs to
    ///      the current bond auctioneer.
    /// @param vault_ The vault.
    /// @return tracked Whether a market is tracked for the vault.
    /// @return marketId The tracked market id; zero when none is tracked.
    function trackedMarket(address vault_) external view returns (bool tracked, uint256 marketId);

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

    /// @notice Returns the gas limit of an isolated step: the weekly reset of a vault,
    ///         the processing of the purchased OHM, the daily cycle of a vault, and the
    ///         sweep of a vault by `returnFundsToTreasury` each run with this amount of
    ///         gas.
    /// @dev `IPeriodicTask.execute` and `returnFundsToTreasury` revert with
    ///      `IYieldRepurchaseFacilityV2_InsufficientStepGas` when the gas remaining
    ///      before a step does not cover the limit, the one 64th of the gas that the
    ///      calling frame keeps back from a call (EIP-150), and a fixed margin.
    /// @return The gas limit of one isolated step, in gas units.
    function stepGasLimit() external view returns (uint32);

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

    /// @notice Returns the dependencies of the facility: the Kernel modules, the OHM token,
    ///         the backing oracle and vault, the bond contracts, and the market parameters.
    /// @dev The values are the ones the individual getters report at the time of the call,
    ///      assembled into one structure.
    /// @return The dependencies of the facility.
    function context() external view returns (Context memory);

    /// @notice Returns the exclusive upper bound of the re-enable grace window, in
    ///         seconds: the window must be strictly shorter than one weekly cycle.
    /// @return The bound, in seconds.
    // solhint-disable-next-line func-name-mixedcase
    function MAX_GRACE_PERIOD() external view returns (uint32);
}
