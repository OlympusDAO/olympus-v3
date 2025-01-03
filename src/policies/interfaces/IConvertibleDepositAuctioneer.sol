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
    event TickStepUpdated(uint24 newTickStep);

    /// @notice Emitted when the contract is activated
    event Activated();

    /// @notice Emitted when the contract is deactivated
    event Deactivated();

    // ========== ERRORS ========== //

    /// @notice Emitted when the parameters are invalid
    ///
    /// @param  reason          Reason for invalid parameters
    error CDAuctioneer_InvalidParams(string reason);

    /// @notice Emitted when the contract is not active
    error CDAuctioneer_NotActive();

    /// @notice Emitted when the state is invalid
    error CDAuctioneer_InvalidState();

    // ========== DATA STRUCTURES ========== //

    /// @notice State of the auction
    ///
    /// @param  target          Number of OHM available to sell per day
    /// @param  tickSize        Number of OHM in a tick
    /// @param  minPrice        Minimum price that OHM can be sold for, in terms of the bid token
    /// @param  lastUpdate      Timestamp of last update to current tick
    /// @param  timeToExpiry    Time between creation and expiry of deposit
    struct State {
        uint256 target;
        uint256 tickSize;
        uint256 minPrice;
        uint48 lastUpdate;
        uint48 timeToExpiry;
    }

    /// @notice Tracks auction activity for a given day
    ///
    /// @param  deposits        Quantity of bid tokens deposited for the day
    /// @param  convertible     Quantity of OHM that will be issued for the day's deposits
    struct Day {
        uint256 deposits;
        uint256 convertible;
    }

    /// @notice Information about a tick
    ///
    /// @param  price           Price of the tick, in terms of the bid token
    /// @param  capacity        Capacity of the tick, in terms of OHM
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

    /// @notice Get the amount of OHM tokens that could be converted for a bid
    ///
    /// @param  bidAmount_      Amount of reserve tokens
    /// @return ohmOut          Amount of OHM tokens that the bid amount could be converted to
    /// @return depositSpender  The address of the contract that would spend the reserve tokens
    function previewBid(
        uint256 bidAmount_
    ) external view returns (uint256 ohmOut, address depositSpender);

    // ========== STATE VARIABLES ========== //

    /// @notice Get the current tick of the auction
    ///
    /// @return tick Tick info
    function getCurrentTick() external view returns (Tick memory tick);

    /// @notice Get the current state of the auction
    ///
    /// @return state State info
    function getState() external view returns (State memory state);

    /// @notice Get the auction state for the current day
    ///
    /// @return day Day info
    function getDayState() external view returns (Day memory day);

    /// @notice The multiplier applied to the conversion price at every tick, in terms of `ONE_HUNDRED_PERCENT`
    /// @dev    This is stored as a percentage, where 100e2 = 100% (no increase)
    ///
    /// @return tickStep The tick step, in terms of `ONE_HUNDRED_PERCENT`
    function getTickStep() external view returns (uint24 tickStep);

    /// @notice The token that is being bid
    ///
    /// @return token The token that is being bid
    function bidToken() external view returns (address token);

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

    /// @notice Sets the multiplier applied to the conversion price at every tick, in terms of `ONE_HUNDRED_PERCENT`
    /// @dev    See `getTickStep()` for more information
    ///
    /// @param  newStep_     new tick step, in terms of `ONE_HUNDRED_PERCENT`
    function setTickStep(uint24 newStep_) external;
}
