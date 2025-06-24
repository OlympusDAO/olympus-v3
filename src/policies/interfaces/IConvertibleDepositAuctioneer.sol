// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {IERC20} from "src/interfaces/IERC20.sol";

/// @title  IConvertibleDepositAuctioneer
/// @notice Interface for a contract that runs auctions for a single deposit token to convert to a convertible deposit token
interface IConvertibleDepositAuctioneer {
    // ========== EVENTS ========== //

    /// @notice Emitted when a bid is made
    ///
    /// @param  bidder            The address of the bidder
    /// @param  depositAsset      The asset that is being deposited
    /// @param  depositPeriod     The deposit period
    /// @param  depositAmount     The amount of deposit asset that was deposited
    /// @param  convertedAmount   The amount of OHM that can be converted
    /// @param  positionId        The ID of the position created by the DEPOS module to represent the convertible deposit terms
    event Bid(
        address indexed bidder,
        address indexed depositAsset,
        uint8 indexed depositPeriod,
        uint256 depositAmount,
        uint256 convertedAmount,
        uint256 positionId
    );

    /// @notice Emitted when the auction parameters are updated
    ///
    /// @param  newTarget       Target for OHM sold per day
    /// @param  newTickSize     Number of OHM in a tick
    /// @param  newMinPrice     Minimum tick price
    event AuctionParametersUpdated(uint256 newTarget, uint256 newTickSize, uint256 newMinPrice);

    /// @notice Emitted when the auction result is recorded
    ///
    /// @param  ohmConvertible  Amount of OHM that was converted
    /// @param  target          Target for OHM sold per day
    /// @param  periodIndex     The index of the auction result in the tracking period
    event AuctionResult(uint256 ohmConvertible, uint256 target, uint8 periodIndex);

    /// @notice Emitted when the tick step is updated
    ///
    /// @param  newTickStep     Percentage increase (decrease) per tick
    event TickStepUpdated(uint24 newTickStep);

    /// @notice Emitted when the auction tracking period is updated
    ///
    /// @param  newAuctionTrackingPeriod The number of days that auction results are tracked for
    event AuctionTrackingPeriodUpdated(uint8 newAuctionTrackingPeriod);

    /// @notice Emitted when a deposit period is enabled
    ///
    /// @param  depositAsset      The asset that is being deposited
    /// @param  depositPeriod     The deposit period
    event DepositPeriodEnabled(address depositAsset, uint8 depositPeriod);

    /// @notice Emitted when a deposit period is disabled
    ///
    /// @param  depositAsset      The asset that is being deposited
    /// @param  depositPeriod     The deposit period
    event DepositPeriodDisabled(address depositAsset, uint8 depositPeriod);

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

    /// @notice Emitted when the deposit period is already enabled for this asset
    error CDAuctioneer_DepositPeriodAlreadyEnabled(address depositAsset, uint8 depositPeriod);

    /// @notice Emitted when the deposit period is not enabled for this asset
    error CDAuctioneer_DepositPeriodNotEnabled(address depositAsset, uint8 depositPeriod);

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
    /// @param  initTimestamp   Timestamp when the day state was initialized
    /// @param  convertible     Quantity of OHM that will be issued for the day's deposits
    struct Day {
        uint48 initTimestamp;
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

    /// @notice Parameters provided to the `enable()` function
    ///
    /// @param  target                  Number of OHM available to sell per day
    /// @param  tickSize                Number of OHM in a tick
    /// @param  minPrice                Minimum price that OHM can be sold for, in terms of the bid token
    /// @param  tickStep                Percentage increase (decrease) per tick
    /// @param  auctionTrackingPeriod   Number of days that auction results are tracked for
    struct EnableParams {
        uint256 target;
        uint256 tickSize;
        uint256 minPrice;
        uint24 tickStep;
        uint8 auctionTrackingPeriod;
    }

    // ========== AUCTION ========== //

    /// @notice Deposit bid tokens to bid for convertible deposit tokens
    ///
    /// @param  depositAsset_   The asset that is being deposited
    /// @param  depositPeriod_  The deposit period
    /// @param  depositAmount_  Amount of deposit asset to deposit
    /// @param  wrapPosition_   Whether to wrap the position as an ERC721
    /// @param  wrapReceipt_    Whether to wrap the receipt as an ERC20
    /// @return ohmOut          Amount of OHM tokens that the deposit can be converted to
    /// @return positionId      The ID of the position created by the DEPOS module to represent the convertible deposit terms
    /// @return receiptTokenId  The ID of the receipt token created by the DepositManager to represent the deposit
    function bid(
        IERC20 depositAsset_,
        uint8 depositPeriod_,
        uint256 depositAmount_,
        bool wrapPosition_,
        bool wrapReceipt_
    ) external returns (uint256 ohmOut, uint256 positionId, uint256 receiptTokenId);

    /// @notice Get the amount of OHM tokens that could be converted for a bid
    ///
    /// @param  depositAsset_   The asset that is being deposited
    /// @param  depositPeriod_  The deposit period
    /// @param  deposit_        Amount of deposit asset to deposit
    /// @return ohmOut          Amount of OHM tokens that the deposit could be converted to
    /// @return depositSpender  The address of the contract that would spend the deposit asset
    function previewBid(
        IERC20 depositAsset_,
        uint8 depositPeriod_,
        uint256 deposit_
    ) external view returns (uint256 ohmOut, address depositSpender);

    // ========== STATE VARIABLES ========== //

    /// @notice Get the previous tick of the auction
    ///
    /// @return tick Tick info
    function getPreviousTick(
        IERC20 depositAsset_,
        uint8 depositPeriod_
    ) external view returns (Tick memory tick);

    /// @notice Calculate the current tick of the auction
    /// @dev    This function should calculate the current tick based on the previous tick and the time passed since the last update
    ///
    /// @return tick Tick info
    function getCurrentTick(
        IERC20 depositAsset_,
        uint8 depositPeriod_
    ) external view returns (Tick memory tick);

    /// @notice Get the current tick size
    ///
    /// @return tickSize The current tick size
    function getCurrentTickSize() external view returns (uint256 tickSize);

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

    /// @notice Get the number of days that auction results are tracked for
    ///
    /// @return daysTracked The number of days that auction results are tracked for
    function getAuctionTrackingPeriod() external view returns (uint8 daysTracked);

    /// @notice Get the auction results for the tracking period
    ///
    /// @return results The auction results, where a positive number indicates an over-subscription for the day.
    function getAuctionResults() external view returns (int256[] memory results);

    /// @notice Get the index of the next auction result
    ///
    /// @return index The index where the next auction result will be stored
    function getAuctionResultsNextIndex() external view returns (uint8 index);

    // ========== ASSET CONFIGURATION ========== //

    /// @notice Get the deposit assets
    ///
    /// @return assets The deposit assets
    function getDepositAssets() external view returns (IERC20[] memory assets);

    /// @notice Get the deposit periods for a deposit asset
    ///
    /// @param  depositAsset_   The asset that is being deposited
    /// @return periods The deposit periods
    function getDepositPeriods(IERC20 depositAsset_) external view returns (uint8[] memory periods);

    /// @notice Get the number of deposit asset and period combinations that are enabled
    ///
    /// @return count The number of deposit asset and period combinations
    function getDepositAssetsAndPeriodsCount() external view returns (uint256 count);

    /// @notice Returns whether a deposit asset and period combination is enabled
    ///
    /// @param  depositAsset_   The asset that is being deposited
    /// @param  depositPeriod_  The deposit period
    /// @return isEnabled       Whether the deposit asset is enabled
    function isDepositEnabled(
        IERC20 depositAsset_,
        uint8 depositPeriod_
    ) external view returns (bool isEnabled);

    /// @notice Enables a deposit asset and period combination
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Enabling the deposit asset and period combination
    ///         - Emitting an event
    ///
    /// @param  depositAsset_   The asset that is being deposited
    /// @param  depositPeriod_  The deposit period
    function enableDepositPeriod(IERC20 depositAsset_, uint8 depositPeriod_) external;

    /// @notice Disables a deposit asset and period combination
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Disabling the deposit asset and period combination
    ///         - Emitting an event
    ///
    /// @param  depositAsset_   The asset that is being deposited
    /// @param  depositPeriod_  The deposit period
    function disableDepositPeriod(IERC20 depositAsset_, uint8 depositPeriod_) external;

    // ========== ADMIN ========== //

    /// @notice Update the auction parameters
    /// @dev    This function is expected to be called periodically.
    ///         Only callable by the auction admin
    ///
    /// @param  target_        new target sale per day
    /// @param  tickSize_      new size per tick
    /// @param  minPrice_      new minimum tick price
    function setAuctionParameters(uint256 target_, uint256 tickSize_, uint256 minPrice_) external;

    /// @notice Sets the multiplier applied to the conversion price at every tick, in terms of `ONE_HUNDRED_PERCENT`
    /// @dev    See `getTickStep()` for more information
    ///         Only callable by the admin
    ///
    /// @param  tickStep_     new tick step, in terms of `ONE_HUNDRED_PERCENT`
    function setTickStep(uint24 tickStep_) external;

    /// @notice Set the number of days that auction results are tracked for
    /// @dev    Only callable by the admin
    ///
    /// @param  days_ The number of days that auction results are tracked for
    function setAuctionTrackingPeriod(uint8 days_) external;
}
