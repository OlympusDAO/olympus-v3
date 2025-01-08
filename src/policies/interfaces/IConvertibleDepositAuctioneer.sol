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

    /// @notice Emitted when the contract is not initialized
    error CDAuctioneer_NotInitialized();

    // ========== DATA STRUCTURES ========== //

    /// @notice Auction parameters
    /// @dev    These values should only be set through the `setAuctionParameters()` function
    ///
    /// @param  target          Number of OHM available to sell per day
    /// @param  tickSize        Number of OHM in a tick
    /// @param  minPrice        Minimum price that OHM can be sold for, in terms of the bid token
    struct AuctionParameters {
        uint256 target;
        uint256 tickSize;
        uint256 minPrice;
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
    /// @param  lastUpdate      Timestamp of last update to the tick
    struct Tick {
        uint256 price;
        uint256 capacity;
        uint48 lastUpdate;
    }

    // ========== AUCTION ========== //

    /// @notice Deposit reserve tokens to bid for convertible deposit tokens
    ///
    /// @param  deposit_        Amount of reserve tokens to deposit
    /// @return ohmOut          Amount of OHM tokens that the deposit can be converted to
    /// @return positionId      The ID of the position created by the CDPOS module to represent the convertible deposit terms
    function bid(uint256 deposit_) external returns (uint256 ohmOut, uint256 positionId);

    /// @notice Get the amount of OHM tokens that could be converted for a bid
    ///
    /// @param  bidAmount_      Amount of reserve tokens
    /// @return ohmOut          Amount of OHM tokens that the bid amount could be converted to
    /// @return depositSpender  The address of the contract that would spend the reserve tokens
    function previewBid(
        uint256 bidAmount_
    ) external view returns (uint256 ohmOut, address depositSpender);

    // ========== STATE VARIABLES ========== //

    /// @notice Get the previous tick of the auction
    ///
    /// @return tick Tick info
    function getPreviousTick() external view returns (Tick memory tick);

    /// @notice Calculate the current tick of the auction
    /// @dev    This function should calculate the current tick based on the previous tick and the time passed since the last update
    ///
    /// @return tick Tick info
    function getCurrentTick() external view returns (Tick memory tick);

    /// @notice Get the current auction parameters
    ///
    /// @return auctionParameters Auction parameters
    function getAuctionParameters()
        external
        view
        returns (AuctionParameters memory auctionParameters);

    /// @notice Get the auction state for the current day
    ///
    /// @return day Day info
    function getDayState() external view returns (Day memory day);

    /// @notice The multiplier applied to the conversion price at every tick, in terms of `ONE_HUNDRED_PERCENT`
    /// @dev    This is stored as a percentage, where 100e2 = 100% (no increase)
    ///
    /// @return tickStep The tick step, in terms of `ONE_HUNDRED_PERCENT`
    function getTickStep() external view returns (uint24 tickStep);

    /// @notice Get the number of seconds between creation and expiry of convertible deposits
    ///
    /// @return timeToExpiry The time to expiry
    function getTimeToExpiry() external view returns (uint48 timeToExpiry);

    /// @notice The token that is being bid
    ///
    /// @return token The token that is being bid
    function bidToken() external view returns (address token);

    // ========== ADMIN ========== //

    /// @notice Update the auction parameters
    /// @dev    only callable by the auction admin
    ///
    /// @param  target_        new target sale per day
    /// @param  tickSize_      new size per tick
    /// @param  minPrice_      new minimum tick price
    /// @return remainder      amount of ohm not sold
    function setAuctionParameters(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_
    ) external returns (uint256 remainder);

    /// @notice Set the time to expiry
    /// @dev    See `getTimeToExpiry()` for more information
    ///         Only callable by the admin
    ///
    /// @param  timeToExpiry_     new time to expiry
    function setTimeToExpiry(uint48 timeToExpiry_) external;

    /// @notice Sets the multiplier applied to the conversion price at every tick, in terms of `ONE_HUNDRED_PERCENT`
    /// @dev    See `getTickStep()` for more information
    ///         Only callable by the admin
    ///
    /// @param  tickStep_     new tick step, in terms of `ONE_HUNDRED_PERCENT`
    function setTickStep(uint24 tickStep_) external;

    /// @notice Enables governance to initialize and activate the contract. This ensures that the contract is in a valid state when activated.
    /// @dev    Only callable by the admin role
    ///
    /// @param  target_          The target for OHM sold per day
    /// @param  tickSize_        The size of each tick
    /// @param  minPrice_        The minimum price that OHM can be sold for, in terms of the bid token
    /// @param  tickStep_        The tick step, in terms of `ONE_HUNDRED_PERCENT`
    /// @param  timeToExpiry_    The number of seconds between creation and expiry of convertible deposits
    function initialize(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_,
        uint24 tickStep_,
        uint48 timeToExpiry_
    ) external;

    /// @notice Activate the contract functionality
    /// @dev    Only callable by the emergency role
    function activate() external;

    /// @notice Deactivate the contract functionality
    /// @dev    Only callable by the emergency role
    function deactivate() external;
}
