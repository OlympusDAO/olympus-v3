// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

/// @title  IConvertibleDepositAuctioneer
/// @notice Interface for a contract that runs auctions for convertible deposit tokens
interface IConvertibleDepositAuctioneer {
    // ========== EVENTS ========== //

    /// @notice Emitted when the auction parameters are updated
    ///
    /// @param  newTarget       Target for OHM sold per day
    /// @param  newTickSize     Number of OHM in a tick
    /// @param  newMinPrice     Minimum tick price
    event AuctionParametersUpdated(uint256 newTarget, uint256 newTickSize, uint256 newMinPrice);

    /// @notice Emitted when the time to expiry is updated
    ///
    /// @param  newTimeToExpiry Time to expiry
    event TimeToExpiryUpdated(uint48 newTimeToExpiry);

    /// @notice Emitted when the tick step is updated
    ///
    /// @param  newTickStep     Percentage increase (decrease) per tick
    event TickStepUpdated(uint256 newTickStep);

    // ========== ERRORS ========== //

    /// @notice Emitted when the parameters are invalid
    ///
    /// @param  reason          Reason for invalid parameters
    error CDAuctioneer_InvalidParams(string reason);

    // ========== DATA STRUCTURES ========== //

    // TODO document decimals for State.price, Tick.price

    /// @notice State of the auction
    ///
    /// @param  target          Number of OHM available to sell per day
    /// @param  tickSize        Number of OHM in a tick
    /// @param  minPrice        Minimum price that OHM can be sold for
    /// @param  tickStep        Percentage increase (decrease) per tick, in terms of `decimals`.
    /// @param  lastUpdate      Timestamp of last update to current tick
    /// @param  timeToExpiry    Time between creation and expiry of deposit
    struct State {
        uint256 target;
        uint256 tickSize;
        uint256 minPrice;
        uint256 tickStep;
        uint48 lastUpdate;
        uint48 timeToExpiry;
    }

    /// @notice Tracks auction activity for a given day
    ///
    /// @param  deposits        total deposited for day
    /// @param  convertible     total convertible for day
    struct Day {
        uint256 deposits;
        uint256 convertible;
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

    /// @notice Deposit reserve tokens to bid for convertible deposit tokens
    ///
    /// @param  deposit_        Amount of reserve tokens to deposit
    /// @return ohmOut          Amount of OHM tokens that the deposit can be converted to
    function bid(uint256 deposit_) external returns (uint256 ohmOut);

    /// @notice Get the amount of OHM tokens issued for a deposit
    ///
    /// @param  deposit_        Amount of reserve tokens
    /// @return ohmOut          Amount of OHM tokens
    function previewBid(uint256 deposit_) external view returns (uint256 ohmOut);

    // ========== STATE VARIABLES ========== //

    /// @notice Get the current tick of the auction
    ///
    /// @return tick Tick info
    function getCurrentTick() external view returns (Tick memory tick);

    /// @notice Get the current state of the auction
    ///
    /// @return state State info
    function getState() external view returns (State memory state);

    /// @notice Get the auction activity for the current day
    ///
    /// @return day Day info
    function getDay() external view returns (Day memory day);

    // ========== ADMIN ========== //

    /// @notice Update the auction parameters
    /// @dev    only callable by the auction admin
    ///
    /// @param  newTarget_     new target sale per day
    /// @param  newSize_       new size per tick
    /// @param  newMinPrice_   new minimum tick price
    /// @return remainder      amount of ohm not sold
    function setAuctionParameters(
        uint256 newTarget_,
        uint256 newSize_,
        uint256 newMinPrice_
    ) external returns (uint256 remainder);

    /// @notice Set the time to expiry
    /// @dev    only callable by the admin
    ///
    /// @param  newTime_     new time to expiry
    function setTimeToExpiry(uint48 newTime_) external;

    /// @notice Set the percentage increase/decrease when a tick is filled, in terms of `decimals`.
    ///         A tick step of 1e18 (assuming 18 decimals) will result in no change to the tick price, whereas a tick step of 9e17 will result in a 10% decrease.
    /// @dev    This function should only be callable by the admin
    ///
    /// @param  newStep_     new tick step, in terms of `decimals`.
    function setTickStep(uint256 newStep_) external;
}
