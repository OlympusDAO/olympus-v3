// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IConvertibleDepositAuctioneer {
    // ========== EVENTS ========== //

    // ========== ERRORS ========== //

    error CDAuctioneer_InvalidParams(string reason);

    // ========== DATA STRUCTURES ========== //

    /// @notice State of the auction
    ///
    /// @param  target          number of ohm per day
    /// @param  tickSize        number of ohm in a tick
    /// @param  minPrice        minimum tick price
    /// @param  tickStep        percentage increase (decrease) per tick
    /// @param  timeToExpiry    time between creation and expiry of deposit
    /// @param  lastUpdate      timestamp of last update to current tick
    struct State {
        uint256 target;
        uint256 tickSize;
        uint256 minPrice;
        uint256 tickStep;
        uint256 timeToExpiry;
        uint256 lastUpdate;
    }

    /// @notice Tracks auction activity for a given day
    ///
    /// @param  deposits        total deposited for day
    /// @param  convertable     total convertable for day
    struct Day {
        uint256 deposits;
        uint256 convertable;
    }

    /// @notice Information about a tick
    ///
    /// @param  price           price of the tick
    /// @param  capacity        capacity of the tick
    struct Tick {
        uint256 price;
        uint256 capacity;
    }

    // ========== AUCTION ========== //

    /// @notice Use a deposit to bid for CDs
    ///
    /// @param  deposit     amount of reserve tokens
    /// @return convertable amount of convertable tokens
    function bid(uint256 deposit) external returns (uint256 convertable);

    // ========== VIEW ========== //

    /// @notice Get the current tick
    ///
    /// @return tick info in Tick struct
    function getCurrentTick() external view returns (Tick memory tick);

    /// @notice Get the current state
    ///
    /// @return state info in State struct
    function getState() external view returns (State memory state);

    /// @notice Get the auction activity for the current day
    ///
    /// @return day info in Day struct
    function getDay() external view returns (Day memory day);

    /// @notice Get the amount of convertable tokens for a deposit at a given price
    ///
    /// @param  deposit     amount of reserve tokens
    /// @param  price       price of the tick
    /// @return convertable amount of convertable tokens
    function convertFor(uint256 deposit, uint256 price) external view returns (uint256 convertable);

    // ========== ADMIN ========== //

    /// @notice Update the auction parameters
    /// @dev    only callable by the auction admin
    ///
    /// @param  newTarget     new target sale per day
    /// @param  newSize       new size per tick
    /// @param  newMinPrice   new minimum tick price
    /// @return remainder     amount of ohm not sold
    function beat(
        uint256 newTarget,
        uint256 newSize,
        uint256 newMinPrice
    ) external returns (uint256 remainder);

    /// @notice Set the time to expiry
    /// @dev    only callable by the admin
    ///
    /// @param  newTime     new time to expiry
    function setTimeToExpiry(uint256 newTime) external;

    /// @notice Set the tick step
    /// @dev    only callable by the admin
    ///
    /// @param  newStep     new tick step
    function setTickStep(uint256 newStep) external;
}
