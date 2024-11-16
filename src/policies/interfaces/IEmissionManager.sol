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
    error NotActive();
    error AlreadyActive();

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

    /// @notice Emitted when the contract is activated
    event Activated();

    /// @notice Emitted when the contract is deactivated
    event Deactivated();

    // ========== DATA STRUCTURES ========== //

    struct BaseRateChange {
        uint256 changeBy;
        uint48 daysLeft;
        bool addition;
    }

    // ========== EXECUTE ========== //

    /// @notice calculate and execute sale, if applicable, once per day (every 3 beats)
    /// @dev this function is restricted to the heart role and is called on each heart beat
    /// @dev if the contract is not active, the function does nothing
    function execute() external;

    // ========== VIEW ========== //

    function getPremium() external view returns (uint256);
    function minimumPremium() external view returns (uint256);
}
