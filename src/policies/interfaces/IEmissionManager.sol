// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

interface IEmissionManager {
    // ========== ERRORS ========== //

    error OnlyTeller();
    error InvalidMarket();
    error InvalidCallback();
    error InvalidParam(string parameter);
    error CannotRestartYet(uint48 availableAt);
    error RestartTimeframePassed();

    // ========== EVENTS ========== //

    event SaleCreated(uint256 marketID, uint256 saleAmount);
    event BackingUpdated(uint256 newBacking, uint256 supplyAdded, uint256 reservesAdded);

    /// @notice Emitted when the base emission rate is changed
    event BaseRateChanged(uint256 changeBy, uint48 forNumBeats, bool add);

    /// @notice Emitted when the minimum premium is changed
    event MinimumPremiumChanged(uint256 newMinimumPremium);

    /// @notice Emitted when the vesting period is changed
    event VestingPeriodChanged(uint48 newVestingPeriod);

    /// @notice Emitted when the backing is changed
    ///         This differs from `BackingUpdated` in that it is emitted when the backing is changed directly by governance
    event BackingChanged(uint256 newBacking);

    /// @notice Emitted when the restart timeframe is changed
    event RestartTimeframeChanged(uint48 newRestartTimeframe);

    /// @notice Emitted when the bond contracts are set
    event BondContractsSet(address auctioneer, address teller);

    /// @notice Emitted when the CD auctionner contract is set
    event ConvertibleDepositAuctioneerSet(address auctioneer);

    /// @notice Emitted when the tick size scalar is changed
    event TickSizeScalarChanged(uint256 newTickSizeScalar);

    /// @notice Emitted when the minimum price scalar is changed
    event MinPriceScalarChanged(uint256 newMinPriceScalar);

    // ========== DATA STRUCTURES ========== //

    struct BaseRateChange {
        uint256 changeBy;
        uint48 daysLeft;
        bool addition;
    }

    /// @notice Parameters for the `enable` function
    ///
    /// @param baseEmissionsRate    percent of OHM supply to issue per day at the minimum premium, in OHM scale, i.e. 1e9 = 100%
    /// @param minimumPremium       minimum premium at which to issue OHM, a percentage where 1e18 is 100%
    /// @param backing              backing price of OHM in reserve token, in reserve scale
    /// @param tickSizeScalar       scalar for tick size
    /// @param minPriceScalar       scalar for min price
    /// @param restartTimeframe     time in seconds that the manager needs to be restarted after a shutdown, otherwise it must be re-initialized
    struct EnableParams {
        uint256 baseEmissionsRate;
        uint256 minimumPremium;
        uint256 backing;
        uint256 tickSizeScalar;
        uint256 minPriceScalar;
        uint48 restartTimeframe;
    }
}
