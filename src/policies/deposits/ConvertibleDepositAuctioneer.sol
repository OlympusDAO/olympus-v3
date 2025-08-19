// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Libraries
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/deposits/IConvertibleDepositFacility.sol";

// Bophades dependencies
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ConvertibleDepositFacility} from "src/policies/deposits/ConvertibleDepositFacility.sol";

/// @title  Convertible Deposit Auctioneer
/// @notice Implementation of the {IConvertibleDepositAuctioneer} interface for a specific deposit token and 1 or more deposit periods
/// @dev    This contract implements an auction for convertible deposit tokens. It runs these auctions according to the following principles:
///         - Auctions are of infinite duration
///         - Auctions are of infinite capacity
///         - Users place bids by supplying an amount of the configured bid token
///         - The payout token is a receipt token (managed by {DepositManager}), which can be converted to OHM at the price that was set at the time of the bid
///         - During periods of greater demand, the conversion price will increase
///         - During periods of lower demand, the conversion price will decrease
///         - The auction has a minimum price, below which the conversion price will not decrease
///         - The auction has a target amount of convertible OHM to sell per day
///         - When the target is reached, the amount of OHM required to increase the conversion price will decrease, resulting in more rapid price increases (assuming there is demand)
///         - The auction parameters are able to be updated in order to tweak the auction's behaviour
contract ConvertibleDepositAuctioneer is
    IConvertibleDepositAuctioneer,
    Policy,
    PolicyEnabler,
    ReentrancyGuard
{
    using FullMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ========== CONSTANTS ========== //

    /// @notice The role that can perform periodic actions, such as updating the auction parameters
    bytes32 public constant ROLE_EMISSION_MANAGER = "cd_emissionmanager";

    /// @notice Scale of the OHM token
    uint256 internal constant _ohmScale = 1e9;

    uint24 public constant ONE_HUNDRED_PERCENT = 100e2;

    /// @notice The length of the enable parameters
    uint256 internal constant _ENABLE_PARAMS_LENGTH = 160;

    /// @notice The minimum tick size
    uint256 internal constant _TICK_SIZE_MINIMUM = 1;

    // ========== STRUCTS ========== //

    struct BidOutput {
        uint256 tickCapacity;
        uint256 tickPrice;
        uint256 tickSize;
        uint256 depositIn;
        uint256 ohmOut;
    }

    struct BidParams {
        uint8 depositPeriod;
        uint256 depositAmount;
        uint256 minOhmOut;
        bool wrapPosition;
        bool wrapReceipt;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice Whether the deposit period is enabled
    mapping(uint8 depositPeriod => bool isEnabled) internal _depositPeriodsEnabled;

    /// @notice The deposit asset
    IERC20 internal immutable _DEPOSIT_ASSET;

    /// @notice Array of deposit periods
    EnumerableSet.UintSet internal _depositPeriods;

    /// @notice The number of deposit periods that are enabled
    uint256 internal _depositPeriodsCount;

    /// @notice Previous tick for each deposit period
    /// @dev    Use `getCurrentTick()` to recalculate and access the latest data
    mapping(uint8 depositPeriod => Tick previousTick) internal _depositPeriodPreviousTicks;

    /// @notice Address of the Convertible Deposit Facility
    ConvertibleDepositFacility public immutable CD_FACILITY;

    /// @notice Auction parameters
    /// @dev    These values should only be set through the `setAuctionParameters()` function
    AuctionParameters internal _auctionParameters;

    /// @notice The current tick size
    uint256 internal _currentTickSize;

    /// @notice Auction state for the day
    Day internal _dayState;

    /// @notice The tick step
    /// @dev    See `getTickStep()` for more information
    uint24 internal _tickStep;

    /// @notice The index of the next auction result
    uint8 internal _auctionResultsNextIndex;

    /// @notice The number of days that auction results are tracked for
    uint8 internal _auctionTrackingPeriod;

    /// @notice The auction results, where a positive number indicates an over-subscription for the day.
    /// @dev    The length of this array is equal to the auction tracking period
    int256[] internal _auctionResults;

    // ========== SETUP ========== //

    constructor(
        address kernel_,
        address cdFacility_,
        address depositAsset_
    ) Policy(Kernel(kernel_)) {
        if (cdFacility_ == address(0))
            revert ConvertibleDepositAuctioneer_InvalidParams("cd facility");
        if (depositAsset_ == address(0))
            revert ConvertibleDepositAuctioneer_InvalidParams("deposit asset");

        CD_FACILITY = ConvertibleDepositFacility(cdFacility_);
        _DEPOSIT_ASSET = IERC20(depositAsset_);

        // PolicyEnabler makes this disabled until enabled
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {}

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;

        return (major, minor);
    }

    // ========== AUCTION ========== //

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function performs the following:
    ///             - Updates the current tick based on the current state
    ///             - Determines the amount of OHM that can be purchased for the deposit amount, and the updated tick capacity and price
    ///             - Updates the day state, if necessary
    ///             - Creates a convertible deposit position using the deposit amount, the average conversion price and the deposit period
    ///
    ///             This function reverts if:
    ///             - The contract is not active
    ///             - Deposits are not enabled for the asset/period/operator
    ///             - The depositor has not approved the DepositManager to spend the deposit asset
    ///             - The depositor has an insufficient balance of the deposit asset
    ///             - The calculated amount of OHM out is 0
    ///             - The calculated amount of OHM out is < minOhmOut_
    function bid(
        uint8 depositPeriod_,
        uint256 depositAmount_,
        uint256 minOhmOut_,
        bool wrapPosition_,
        bool wrapReceipt_
    )
        external
        override
        nonReentrant
        onlyEnabled
        onlyDepositPeriodEnabled(depositPeriod_)
        returns (uint256, uint256, uint256, uint256)
    {
        return
            _bid(
                BidParams({
                    depositPeriod: depositPeriod_,
                    depositAmount: depositAmount_,
                    minOhmOut: minOhmOut_,
                    wrapPosition: wrapPosition_,
                    wrapReceipt: wrapReceipt_
                })
            );
    }

    /// @notice Internal function to submit an auction bid on the given deposit asset and period
    /// @dev    This function expects the calling function to have already validated the contract state and deposit asset and period
    function _bid(BidParams memory params) internal returns (uint256, uint256, uint256, uint256) {
        uint256 ohmOut;
        uint256 depositIn;
        {
            // Get the current tick for the deposit asset and period
            Tick memory updatedTick = _getCurrentTick(params.depositPeriod);

            // Get bid results
            BidOutput memory output = _previewBid(params.depositAmount, updatedTick);

            // Reject if the OHM out is 0
            if (output.ohmOut == 0) revert ConvertibleDepositAuctioneer_ConvertedAmountZero();

            // Reject if the OHM out is below the minimum OHM out
            if (output.ohmOut < params.minOhmOut)
                revert ConvertibleDepositAuctioneer_ConvertedAmountSlippage(
                    output.ohmOut,
                    params.minOhmOut
                );

            // Update state
            _dayState.convertible += output.ohmOut;

            // Update current tick
            updatedTick.price = output.tickPrice;
            updatedTick.capacity = output.tickCapacity;
            updatedTick.lastUpdate = uint48(block.timestamp);
            _depositPeriodPreviousTicks[params.depositPeriod] = updatedTick;

            // Update the current tick size
            if (output.tickSize != _currentTickSize) {
                _currentTickSize = output.tickSize;
            }

            // Set values for the rest of the function
            ohmOut = output.ohmOut;
            depositIn = output.depositIn;
        }

        // Calculate average price based on the total deposit and ohmOut
        // This is the number of deposit tokens per OHM token
        // We round up to be conservative

        // Create the receipt tokens and position
        (uint256 positionId, uint256 receiptTokenId, uint256 actualAmount) = CD_FACILITY
            .createPosition(
                IConvertibleDepositFacility.CreatePositionParams({
                    asset: _DEPOSIT_ASSET,
                    periodMonths: params.depositPeriod,
                    depositor: msg.sender,
                    amount: depositIn,
                    conversionPrice: depositIn.mulDivUp(_ohmScale, ohmOut), // Assets per OHM, deposit token scale
                    wrapPosition: params.wrapPosition,
                    wrapReceipt: params.wrapReceipt
                })
            );

        // Emit event
        emit Bid(
            msg.sender,
            address(_DEPOSIT_ASSET),
            params.depositPeriod,
            depositIn,
            ohmOut,
            positionId
        );

        return (ohmOut, positionId, receiptTokenId, actualAmount);
    }

    /// @notice Internal function to preview the quantity of OHM tokens that can be purchased for a given deposit amount
    /// @dev    This function performs the following:
    ///         - Cycles through ticks until the deposit is fully converted
    ///         - If the current tick has enough capacity, it will be used
    ///         - If the current tick does not have enough capacity, the remaining capacity will be used. The current tick will then shift to the next tick, resulting in the capacity being filled to the tick size, and the price being multiplied by the tick step.
    ///
    ///         Notes:
    ///         - The function returns the updated tick capacity and price after the bid
    ///         - If the capacity of a tick is depleted (but does not cross into the next tick), the current tick will be shifted to the next one. This ensures that `getCurrentTick()` will not return a tick that has been depleted.
    ///
    /// @param  deposit_            The amount of deposit to be bid
    /// @return output              The output of the bid
    function _previewBid(
        uint256 deposit_,
        Tick memory tick_
    ) internal view returns (BidOutput memory output) {
        uint256 remainingDeposit = deposit_;
        output.tickCapacity = tick_.capacity;
        output.tickPrice = tick_.price;
        output.tickSize = _currentTickSize;

        // Cycle through the ticks until the deposit is fully converted
        while (remainingDeposit > 0) {
            uint256 depositAmount = remainingDeposit;
            uint256 convertibleAmount = _getConvertedDeposit(remainingDeposit, output.tickPrice);

            // No point in continuing if the converted amount is 0
            if (convertibleAmount == 0) break;

            // If there is not enough capacity in the current tick, use the remaining capacity
            if (output.tickCapacity <= convertibleAmount) {
                convertibleAmount = output.tickCapacity;
                // Convertible = deposit * OHM scale / price, so this is the inverse
                depositAmount = convertibleAmount.mulDiv(output.tickPrice, _ohmScale);

                // The tick has also been depleted, so update the price
                output.tickPrice = _getNewTickPrice(output.tickPrice, _tickStep);
                output.tickSize = _getNewTickSize(
                    _dayState.convertible + convertibleAmount + output.ohmOut
                );
                output.tickCapacity = output.tickSize;
            }
            // Otherwise, the tick has enough capacity and needs to be updated
            else {
                output.tickCapacity -= convertibleAmount;
            }

            // Record updates to the deposit and OHM
            remainingDeposit -= depositAmount;
            output.ohmOut += convertibleAmount;
        }

        output.depositIn = deposit_ - remainingDeposit;

        return output;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function previewBid(
        uint8 depositPeriod_,
        uint256 bidAmount_
    )
        external
        view
        override
        onlyEnabled
        onlyDepositPeriodEnabled(depositPeriod_)
        returns (uint256 ohmOut)
    {
        // Get the updated tick based on the current state
        Tick memory currentTick = _getCurrentTick(depositPeriod_);

        // Preview the bid results
        BidOutput memory output = _previewBid(bidAmount_, currentTick);
        ohmOut = output.ohmOut;

        return ohmOut;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Internal function to preview the quantity of OHM tokens that can be purchased for a given deposit amount
    /// @dev    This function does not take into account the capacity of the current tick
    ///
    /// @param  deposit_            The amount of deposit to be converted
    /// @param  price_              The price of the deposit in OHM
    /// @return convertibleAmount   The quantity of OHM tokens that can be purchased
    function _getConvertedDeposit(
        uint256 deposit_,
        uint256 price_
    ) internal pure returns (uint256 convertibleAmount) {
        // As price represents the number of bid tokens per OHM, we can convert the deposit to OHM by dividing by the price and adjusting for the decimal scale
        convertibleAmount = deposit_.mulDiv(_ohmScale, price_);
        return convertibleAmount;
    }

    /// @notice Internal function to preview the new price of the current tick after applying the tick step
    /// @dev    This function does not take into account the capacity of the current tick
    ///
    /// @param  currentPrice_       The current price of the tick in terms of the bid token
    /// @param  tickStep_           The step size of the tick
    /// @return newPrice            The new price of the tick
    function _getNewTickPrice(
        uint256 currentPrice_,
        uint256 tickStep_
    ) internal pure returns (uint256 newPrice) {
        newPrice = currentPrice_.mulDivUp(tickStep_, ONE_HUNDRED_PERCENT);
        return newPrice;
    }

    /// @notice Internal function to calculate the new tick size based on the amount of OHM that has been converted in the current day
    ///
    /// @param  ohmOut_     The amount of OHM that has been converted in the current day
    /// @return newTickSize The new tick size
    function _getNewTickSize(uint256 ohmOut_) internal view returns (uint256 newTickSize) {
        // If the day target is zero, the tick size is always standard
        if (_auctionParameters.target == 0) {
            return _auctionParameters.tickSize;
        }

        // Calculate the multiplier
        uint256 multiplier = ohmOut_ / _auctionParameters.target;

        // If the day target has not been met, the tick size remains the standard
        if (multiplier == 0) {
            newTickSize = _auctionParameters.tickSize;
            return newTickSize;
        }

        // Otherwise the tick size is halved as many times as the multiplier
        newTickSize = _auctionParameters.tickSize / (multiplier * 2);

        // This can round down to zero (which would cause problems with calculations), so provide a fallback
        if (newTickSize == 0) return _TICK_SIZE_MINIMUM;

        return newTickSize;
    }

    function _getCurrentTick(uint8 depositPeriod_) internal view returns (Tick memory tick) {
        // Find amount of time passed and new capacity to add
        uint256 newCapacity;
        {
            Tick memory previousTick = _depositPeriodPreviousTicks[depositPeriod_];
            uint256 timePassed = block.timestamp - previousTick.lastUpdate;
            // The capacity to add is the day target multiplied by the proportion of time passed in a day
            // It is also adjusted by the number of deposit periods that are enabled, otherwise each auction would have too much capacity added
            uint256 capacityToAdd = (_auctionParameters.target * timePassed) /
                1 days /
                _depositPeriodsCount;

            // Skip if the new capacity is 0
            if (capacityToAdd == 0) return previousTick;

            tick = previousTick;
            newCapacity = tick.capacity + capacityToAdd;
        }

        // Iterate over the ticks until the capacity is within the tick size
        // This is the opposite of what happens in the bid function
        // It uses the standard tick size (unaffected by the achievement of the day target),
        // otherwise the tick price would decay quickly
        uint256 tickSize = _auctionParameters.tickSize;
        while (newCapacity > tickSize) {
            // Reduce the capacity by the tick size
            newCapacity -= tickSize;

            // Adjust the tick price by the tick step, in the opposite direction to the bid function
            tick.price = tick.price.mulDivUp(ONE_HUNDRED_PERCENT, _tickStep);

            // Tick price does not go below the minimum
            // Tick capacity is full if the min price is exceeded
            if (tick.price < _auctionParameters.minPrice) {
                tick.price = _auctionParameters.minPrice;
                newCapacity = tickSize;
                break;
            }
        }

        // Set the capacity, but ensure it doesn't exceed the current tick size
        // (which may have been reduced if the day target was met)
        tick.capacity = newCapacity > _currentTickSize ? _currentTickSize : newCapacity;

        return tick;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function calculates the tick at the current time.
    ///
    ///             It uses the following approach:
    ///             - Calculate the added capacity based on the time passed since the last bid, and add it to the current capacity to get the new capacity
    ///             - Until the new capacity is <= to the standard tick size, reduce the capacity by the standard tick size and reduce the price by the tick step
    ///             - If the calculated price is ever lower than the minimum price, the new price is set to the minimum price and the capacity is set to the standard tick size
    ///
    ///             Notes:
    ///             - If the target is 0, the price will not decay and the capacity will not change. It will only decay when a target is set again to a non-zero value.
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The deposit asset and period are not enabled
    function getCurrentTick(
        uint8 depositPeriod_
    )
        external
        view
        onlyEnabled
        onlyDepositPeriodEnabled(depositPeriod_)
        returns (Tick memory tick)
    {
        return _getCurrentTick(depositPeriod_);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function returns the previous tick for the deposit period
    ///             If the deposit period is not configured, all values will be 0
    function getPreviousTick(uint8 depositPeriod_) public view override returns (Tick memory tick) {
        return _depositPeriodPreviousTicks[depositPeriod_];
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getCurrentTickSize() external view override returns (uint256) {
        return _currentTickSize;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getAuctionParameters() external view override returns (AuctionParameters memory) {
        return _auctionParameters;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getDayState() external view override returns (Day memory) {
        return _dayState;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getTickStep() external view override returns (uint24) {
        return _tickStep;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getAuctionTrackingPeriod() external view override returns (uint8) {
        return _auctionTrackingPeriod;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getAuctionResultsNextIndex() external view override returns (uint8) {
        return _auctionResultsNextIndex;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getAuctionResults() external view override returns (int256[] memory) {
        return _auctionResults;
    }

    // ========== ASSET CONFIGURATION ========== //

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getDepositAsset() external view override returns (IERC20) {
        return _DEPOSIT_ASSET;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getDepositPeriods() external view override returns (uint8[] memory) {
        uint256 length = _depositPeriods.length();
        uint8[] memory periods = new uint8[](length);
        for (uint256 i = 0; i < length; i++) {
            periods[i] = uint8(_depositPeriods.at(i));
        }

        return periods;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function isDepositPeriodEnabled(uint8 depositPeriod_) public view override returns (bool) {
        return _depositPeriodsEnabled[depositPeriod_];
    }

    /// @notice Modifier to check if a deposit period is enabled
    modifier onlyDepositPeriodEnabled(uint8 depositPeriod_) {
        if (!isDepositPeriodEnabled(depositPeriod_)) {
            revert ConvertibleDepositAuctioneer_DepositPeriodNotEnabled(
                address(_DEPOSIT_ASSET),
                depositPeriod_
            );
        }
        _;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        Notes:
    ///             - Enabling a deposit period will reset the minimum price and tick size to the standard values
    ///
    ///             This function will revert if:
    ///             - The contract is not enabled
    ///             - The caller is not a manager or admin
    ///             - The deposit period is already enabled for this asset
    function enableDepositPeriod(
        uint8 depositPeriod_
    ) external override onlyEnabled onlyManagerOrAdminRole {
        // Validate that the deposit period is not 0
        if (depositPeriod_ == 0)
            revert ConvertibleDepositAuctioneer_InvalidParams("deposit period");

        // Validate that the deposit period is not already enabled
        if (_depositPeriodsEnabled[depositPeriod_]) {
            revert ConvertibleDepositAuctioneer_DepositPeriodAlreadyEnabled(
                address(_DEPOSIT_ASSET),
                depositPeriod_
            );
        }

        // Update the tick data for all enabled deposit periods
        // This is necessary, otherwise tick capacity and price will be calculated incorrectly
        _updateCurrentTicks();

        // Enable the deposit period
        _depositPeriodsEnabled[depositPeriod_] = true;

        // Add the deposit period to the array if it is not already in it
        if (!_depositPeriods.contains(depositPeriod_)) {
            _depositPeriods.add(depositPeriod_);
        }

        // Initialise the tick
        _depositPeriodPreviousTicks[depositPeriod_] = Tick(
            _auctionParameters.minPrice,
            _auctionParameters.tickSize,
            uint48(block.timestamp)
        );

        // Increment the count
        _depositPeriodsCount++;

        // Emit event
        emit DepositPeriodEnabled(address(_DEPOSIT_ASSET), depositPeriod_);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function will revert if:
    ///             - The contract is not enabled
    ///             - The caller is not a manager or admin
    ///             - The deposit period is not enabled for this asset
    function disableDepositPeriod(
        uint8 depositPeriod_
    ) external override onlyEnabled onlyManagerOrAdminRole {
        // Validate that the deposit period is enabled
        if (!_depositPeriodsEnabled[depositPeriod_]) {
            revert ConvertibleDepositAuctioneer_DepositPeriodNotEnabled(
                address(_DEPOSIT_ASSET),
                depositPeriod_
            );
        }

        // Update the tick data for all enabled deposit periods
        // This is necessary, otherwise tick capacity and price will be calculated incorrectly
        _updateCurrentTicks();

        // Disable the deposit period
        _depositPeriodsEnabled[depositPeriod_] = false;

        // Remove the deposit period from the array
        _depositPeriods.remove(depositPeriod_);

        // Remove the tick
        delete _depositPeriodPreviousTicks[depositPeriod_];

        // Decrement the count
        _depositPeriodsCount--;

        // Emit event
        emit DepositPeriodDisabled(address(_DEPOSIT_ASSET), depositPeriod_);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getDepositPeriodsCount() external view override returns (uint256) {
        return _depositPeriodsCount;
    }

    // ========== ADMIN FUNCTIONS ========== //

    function _setAuctionParameters(uint256 target_, uint256 tickSize_, uint256 minPrice_) internal {
        // The target can be zero

        // Tick size must be non-zero
        if (tickSize_ == 0) revert ConvertibleDepositAuctioneer_InvalidParams("tick size");

        // Min price must be non-zero
        if (minPrice_ == 0) revert ConvertibleDepositAuctioneer_InvalidParams("min price");

        // If the target is non-zero, the tick size must be <= target
        if (target_ > 0 && tickSize_ > target_)
            revert ConvertibleDepositAuctioneer_InvalidParams("tick size");

        _auctionParameters = AuctionParameters(target_, tickSize_, minPrice_);

        // Emit event
        emit AuctionParametersUpdated(address(_DEPOSIT_ASSET), target_, tickSize_, minPrice_);
    }

    function _storeAuctionResults(uint256 previousTarget_) internal {
        // Skip if inactive
        if (!isEnabled) return;

        // If the next index is 0, reset the results before inserting
        // This ensures that the previous results are available for 24 hours
        if (_auctionResultsNextIndex == 0) {
            _auctionResults = new int256[](_auctionTrackingPeriod);
        }

        // Store the auction results
        // Negative values will indicate under-selling
        _auctionResults[_auctionResultsNextIndex] =
            int256(_dayState.convertible) -
            int256(previousTarget_);

        // Emit event
        emit AuctionResult(
            address(_DEPOSIT_ASSET),
            _dayState.convertible,
            previousTarget_,
            _auctionResultsNextIndex
        );

        // Increment the index (or loop around)
        _auctionResultsNextIndex++;
        // Loop around if necessary
        if (_auctionResultsNextIndex >= _auctionTrackingPeriod) {
            _auctionResultsNextIndex = 0;
        }

        // Reset the day state
        _dayState = Day(uint48(block.timestamp), 0);
    }

    /// @notice Sets tick parameters for all enabled deposit periods
    ///
    /// @param  tickSize_           If the new tick size is less than a tick's capacity (or `enforceCapacity_` is true), the tick capacity will be set to this
    /// @param  minPrice_           If the new minimum price is greater than a tick's price (or `enforceMinPrice_` is true), the tick price will be set to this
    /// @param  enforceCapacity_    If true, will set the capacity of each enabled deposit period to the value of `tickSize_`
    /// @param  enforceMinPrice_    If true, will set the price of each enabled deposit period to the value of `minPrice_`
    /// @param  setLastUpdate_      If true, will set the tick's last update to the current timestamp
    function _setNewTickParameters(
        uint256 tickSize_,
        uint256 minPrice_,
        bool enforceCapacity_,
        bool enforceMinPrice_,
        bool setLastUpdate_
    ) internal {
        // Iterate over periods
        uint256 periodLength = _depositPeriods.length();
        for (uint256 j = 0; j < periodLength; j++) {
            uint8 period = uint8(_depositPeriods.at(j));

            // Skip if the deposit period is not enabled
            if (!_depositPeriodsEnabled[period]) continue;

            // Get the previous tick
            Tick storage previousTick = _depositPeriodPreviousTicks[period];

            // Ensure that the tick capacity is not larger than the new tick size
            // Otherwise, excess OHM will be converted
            if (tickSize_ < previousTick.capacity || enforceCapacity_) {
                previousTick.capacity = tickSize_;
            }

            // Ensure that the minimum price is enforced
            // Otherwise, OHM will be converted at a price lower than the minimum
            if (minPrice_ > previousTick.price || enforceMinPrice_) {
                previousTick.price = minPrice_;
            }

            // Set the last update
            if (setLastUpdate_) {
                previousTick.lastUpdate = uint48(block.timestamp);
            }
        }

        // Set the tick size
        // This has the effect of resetting the tick size to the default
        // The tick size may have been adjusted for the previous day if the target was met
        _currentTickSize = tickSize_;
    }

    /// @notice     Takes a snapshot of the current tick values for enabled deposit periods
    function _updateCurrentTicks() internal {
        // Iterate over periods
        uint256 periodLength = _depositPeriods.length();
        for (uint256 i; i < periodLength; i++) {
            uint8 period = uint8(_depositPeriods.at(i));

            // Skip if the deposit period is not enabled
            if (!_depositPeriodsEnabled[period]) continue;

            // Get the current tick for the deposit asset and period
            Tick memory updatedTick = _getCurrentTick(period);
            updatedTick.lastUpdate = uint48(block.timestamp);

            // Update the current tick for the deposit period
            _depositPeriodPreviousTicks[period] = updatedTick;
        }
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function assumes that the the caller is only calling once per period (day), as the contract does not track epochs or timestamps.
    ///
    ///             This function performs the following:
    ///             - Performs validation of the inputs
    ///             - Sets the auction parameters
    ///             - Adjusts the current tick capacity and price, if necessary
    ///             - Resets the tick size to the standard
    ///             - Stores the auction results for the period
    ///
    ///             This function reverts if:
    ///             - The caller does not have the ROLE_EMISSION_MANAGER role
    ///             - The new tick size is 0
    ///             - The new min price is 0
    function setAuctionParameters(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_
    ) external override onlyRole(ROLE_EMISSION_MANAGER) {
        uint256 previousTarget = _auctionParameters.target;

        _setAuctionParameters(target_, tickSize_, minPrice_);

        // The following can be done even if the contract is not active nor initialized, since activating/initializing will set the tick capacity and price

        // Ensure all ticks are updated with the new parameters
        _setNewTickParameters(tickSize_, minPrice_, false, false, false);

        // Store the auction results, if necessary
        _storeAuctionResults(previousTarget);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function will revert if:
    ///             - The caller does not have the ROLE_ADMIN role
    ///             - The new tick step is < 100e2
    ///
    /// @param      newStep_    The new tick step
    function setTickStep(uint24 newStep_) public override onlyManagerOrAdminRole {
        // Value must be more than 100e2
        if (newStep_ < ONE_HUNDRED_PERCENT)
            revert ConvertibleDepositAuctioneer_InvalidParams("tick step");

        _tickStep = newStep_;

        // Emit event
        emit TickStepUpdated(address(_DEPOSIT_ASSET), newStep_);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        Notes:
    ///             - Calling this function will erase the previous auction results, which in turn may affect the bond markets created to sell under-sold OHM capacity
    ///
    ///             This function will revert if:
    ///             - The caller does not have the ROLE_ADMIN role
    ///             - The new auction tracking period is 0
    ///
    /// @param      days_    The new auction tracking period
    function setAuctionTrackingPeriod(uint8 days_) public override onlyManagerOrAdminRole {
        // Value must be non-zero
        if (days_ == 0)
            revert ConvertibleDepositAuctioneer_InvalidParams("auction tracking period");

        _auctionTrackingPeriod = days_;

        // Reset the auction results and index and set to the new length
        _auctionResults = new int256[](days_);
        _auctionResultsNextIndex = 0;

        // Emit event
        emit AuctionTrackingPeriodUpdated(address(_DEPOSIT_ASSET), days_);
    }

    // ========== ACTIVATION/DEACTIVATION ========== //

    /// @inheritdoc PolicyEnabler
    /// @dev        This function will revert if:
    ///             - The enable data is not the correct length
    ///             - The enable data is not an encoded `EnableParams` struct
    ///             - The auction parameters are invalid
    ///             - The tick step is invalid
    ///             - The auction tracking period is invalid
    function _enable(bytes calldata enableData_) internal override {
        if (enableData_.length != _ENABLE_PARAMS_LENGTH)
            revert ConvertibleDepositAuctioneer_InvalidParams("enable data");

        // Decode the enable data
        EnableParams memory params = abi.decode(enableData_, (EnableParams));

        // Set the auction parameters
        _setAuctionParameters(params.target, params.tickSize, params.minPrice);

        // Set the tick step
        setTickStep(params.tickStep);

        // Set the auction tracking period
        setAuctionTrackingPeriod(params.auctionTrackingPeriod);

        // Ensure all ticks have the current parameters
        // Also set the lastUpdate to the current block timestamp
        // Otherwise, getCurrentTick() will calculate a long period of time having passed
        _setNewTickParameters(params.tickSize, params.minPrice, true, true, true);

        // Reset the day state
        _dayState = Day(uint48(block.timestamp), 0);

        // Reset the auction results
        _auctionResults = new int256[](_auctionTrackingPeriod);
        _auctionResultsNextIndex = 0;
    }
}
