// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Libraries
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FullMath} from "src/libraries/FullMath.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

// Bophades dependencies
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {CDFacility} from "./CDFacility.sol";

/// @title  Convertible Deposit Auctioneer
/// @notice Implementation of the IConvertibleDepositAuctioneer interface
/// @dev    This contract implements an auction for convertible deposit tokens. It runs these auctions according to the following principles:
///         - Auctions are of infinite duration
///         - Auctions are of infinite capacity
///         - Users place bids by supplying an amount of the quote token
///         - The quote token is the deposit token from the CDEPO module
///         - The payout token is the CDEPO token, which can be converted to OHM at the conversion price that was set at the time of the bid
///         - During periods of greater demand, the conversion price will increase
///         - During periods of lower demand, the conversion price will decrease
///         - The auction has a minimum price, below which the conversion price will not decrease
///         - The auction has a target amount of convertible OHM to sell per day
///         - When the target is reached, the amount of OHM required to increase the conversion price will decrease, resulting in more rapid price increases (assuming there is demand)
///         - The auction parameters are able to be updated in order to tweak the auction's behaviour
contract CDAuctioneer is IConvertibleDepositAuctioneer, Policy, PolicyEnabler, ReentrancyGuard {
    using FullMath for uint256;

    // ========== CONSTANTS ========== //

    /// @notice The role that can perform periodic actions, such as updating the auction parameters
    bytes32 public constant ROLE_HEART = "cd_emissionmanager";

    /// @notice Scale of the OHM token
    uint256 internal constant _ohmScale = 1e9;

    uint24 public constant ONE_HUNDRED_PERCENT = 100e2;

    /// @notice The length of the enable parameters
    uint256 internal constant _ENABLE_PARAMS_LENGTH = 224;

    // ========== STATE VARIABLES ========== //

    /// @notice Address of the token that is being bid
    IERC20 public immutable BID_TOKEN;

    /// @notice Address of the Convertible Deposit Facility
    CDFacility public immutable CD_FACILITY;

    /// @notice Address of the CDEPO module
    CDEPOv1 public CDEPO;

    /// @notice Address of the CD token
    IConvertibleDepositERC20 public convertibleDebtToken;

    /// @notice Previous tick of the auction
    /// @dev    Use `getCurrentTick()` to recalculate and access the latest data
    Tick internal _previousTick;

    /// @notice Auction parameters
    /// @dev    These values should only be set through the `setAuctionParameters()` function
    AuctionParameters internal _auctionParameters;

    /// @notice Auction state for the day
    Day internal _dayState;

    /// @notice The tick step
    /// @dev    See `getTickStep()` for more information
    uint24 internal _tickStep;

    /// @notice The number of seconds between creation and expiry of convertible deposits
    /// @dev    See `getTimeToExpiry()` for more information
    uint48 internal _timeToExpiry;

    /// @notice The number of seconds that redemption is allowed
    /// @dev    See `getRedemptionPeriod()` for more information
    uint48 internal _redemptionPeriod;

    /// @notice The index of the next auction result
    uint8 internal _auctionResultsNextIndex;

    /// @notice The number of days that auction results are tracked for
    uint8 internal _auctionTrackingPeriod;

    /// @notice The auction results, where a positive number indicates an over-subscription for the day.
    /// @dev    The length of this array is equal to the auction tracking period
    int256[] internal _auctionResults;

    // ========== SETUP ========== //

    constructor(address kernel_, address cdFacility_, address bidToken_) Policy(Kernel(kernel_)) {
        if (cdFacility_ == address(0)) revert CDAuctioneer_InvalidParams("cd facility");
        if (bidToken_ == address(0)) revert CDAuctioneer_InvalidParams("bid token");

        CD_FACILITY = CDFacility(cdFacility_);
        BID_TOKEN = IERC20(bidToken_);

        // PolicyEnabler makes this disabled until enabled
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("CDEPO");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        CDEPO = CDEPOv1(getModuleAddress(dependencies[1]));

        // Validate that the bid token is supported by the CDEPO module
        convertibleDebtToken = CDEPO.getConvertibleDepositToken(address(BID_TOKEN));
        if (address(convertibleDebtToken) == address(0))
            revert CDAuctioneer_InvalidParams("bid token");
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
    ///             - Creates a convertible deposit position using the deposit amount, the average conversion price and the configured time to expiry
    ///
    ///             This function reverts if:
    ///             - The contract is not active
    ///             - The calculated converted amount is 0
    function bid(
        uint256 deposit_
    ) external override nonReentrant onlyEnabled returns (uint256 ohmOut, uint256 positionId) {
        // Update the current tick based on the current state
        // lastUpdate is updated after this, otherwise time calculations will be incorrect
        _previousTick = getCurrentTick();

        // Get bid results
        uint256 currentTickPrice;
        uint256 currentTickCapacity;
        uint256 currentTickSize;
        uint256 depositIn;
        (currentTickCapacity, currentTickPrice, currentTickSize, depositIn, ohmOut) = _previewBid(
            deposit_,
            _previousTick
        );

        // Reject if the OHM out is 0
        if (ohmOut == 0) revert CDAuctioneer_InvalidParams("converted amount");

        // Update state
        _dayState.deposits += depositIn;
        _dayState.convertible += ohmOut;

        // Update current tick
        _previousTick.price = currentTickPrice;
        _previousTick.capacity = currentTickCapacity;
        _previousTick.tickSize = currentTickSize;
        _previousTick.lastUpdate = uint48(block.timestamp);

        // Calculate average price based on the total deposit and ohmOut
        // This is the number of deposit tokens per OHM token
        // We round up to be conservative
        uint256 conversionPrice = depositIn.mulDivUp(_ohmScale, ohmOut);

        // Create the CD tokens and position
        positionId = CD_FACILITY.mint(
            convertibleDebtToken,
            msg.sender,
            depositIn,
            conversionPrice,
            uint48(block.timestamp + _timeToExpiry),
            uint48(block.timestamp + _timeToExpiry + _redemptionPeriod),
            false
        );

        return (ohmOut, positionId);
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
    /// @return updatedTickCapacity The adjusted capacity of the current tick
    /// @return updatedTickPrice    The adjusted price of the current tick
    /// @return updatedTickSize     The adjusted size of the current tick
    /// @return depositIn           The amount of deposit that was converted
    /// @return ohmOut              The quantity of OHM tokens that can be purchased
    function _previewBid(
        uint256 deposit_,
        Tick memory tick_
    )
        internal
        view
        returns (
            uint256 updatedTickCapacity,
            uint256 updatedTickPrice,
            uint256 updatedTickSize,
            uint256 depositIn,
            uint256 ohmOut
        )
    {
        uint256 remainingDeposit = deposit_;
        updatedTickCapacity = tick_.capacity;
        updatedTickPrice = tick_.price;
        updatedTickSize = tick_.tickSize;

        // Cycle through the ticks until the deposit is fully converted
        while (remainingDeposit > 0) {
            uint256 depositAmount = remainingDeposit;
            uint256 convertibleAmount = _getConvertedDeposit(remainingDeposit, updatedTickPrice);

            // No point in continuing if the converted amount is 0
            if (convertibleAmount == 0) break;

            // If there is not enough capacity in the current tick, use the remaining capacity
            if (updatedTickCapacity <= convertibleAmount) {
                convertibleAmount = updatedTickCapacity;
                // Convertible = deposit * OHM scale / price, so this is the inverse
                depositAmount = convertibleAmount.mulDiv(updatedTickPrice, _ohmScale);

                // The tick has also been depleted, so update the price
                updatedTickPrice = _getNewTickPrice(updatedTickPrice, _tickStep);
                updatedTickSize = _getNewTickSize(
                    _dayState.convertible + convertibleAmount + ohmOut
                );
                updatedTickCapacity = updatedTickSize;
            }
            // Otherwise, the tick has enough capacity and needs to be updated
            else {
                updatedTickCapacity -= convertibleAmount;
            }

            // Record updates to the deposit and OHM
            remainingDeposit -= depositAmount;
            ohmOut += convertibleAmount;
        }

        return (
            updatedTickCapacity,
            updatedTickPrice,
            updatedTickSize,
            deposit_ - remainingDeposit,
            ohmOut
        );
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function previewBid(
        uint256 bidAmount_
    ) external view override returns (uint256 ohmOut, address depositSpender) {
        // Get the updated tick based on the current state
        Tick memory currentTick = getCurrentTick();

        // Preview the bid results
        (, , , , ohmOut) = _previewBid(bidAmount_, currentTick);

        return (ohmOut, address(CDEPO));
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
        // Calculate the multiplier
        uint256 multiplier = ohmOut_ / _auctionParameters.target;

        // If the day target has not been met, the tick size remains the standard
        if (multiplier == 0) {
            newTickSize = _auctionParameters.tickSize;
            return newTickSize;
        }

        // Otherwise the tick size is halved as many times as the multiplier
        newTickSize = _auctionParameters.tickSize / (multiplier * 2);
        return newTickSize;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function calculates the tick at the current time.
    ///
    ///             It uses the following approach:
    ///             - Calculate the added capacity based on the time passed since the last bid, and add it to the current capacity to get the new capacity
    ///             - Until the new capacity is <= to the tick size, reduce the capacity by the tick size and reduce the price by the tick step
    ///             - If the calculated price is ever lower than the minimum price, the new price is set to the minimum price and the capacity is set to the tick size
    function getCurrentTick() public view onlyEnabled returns (Tick memory tick) {
        // Find amount of time passed and new capacity to add
        uint256 timePassed = block.timestamp - _previousTick.lastUpdate;
        uint256 capacityToAdd = (_auctionParameters.target * timePassed) / 1 days;

        // Skip if the new capacity is 0
        if (capacityToAdd == 0) return _previousTick;

        tick = _previousTick;
        uint256 newCapacity = tick.capacity + capacityToAdd;

        // Iterate over the ticks until the capacity is within the tick size
        // This is the opposite of what happens in the bid function
        while (newCapacity > tick.tickSize) {
            // Reduce the capacity by the tick size
            newCapacity -= tick.tickSize;

            // Adjust the tick price by the tick step, in the opposite direction to the bid function
            tick.price = tick.price.mulDivUp(ONE_HUNDRED_PERCENT, _tickStep);

            // Tick price does not go below the minimum
            // Tick capacity is full if the min price is exceeded
            if (tick.price < _auctionParameters.minPrice) {
                tick.price = _auctionParameters.minPrice;
                newCapacity = tick.tickSize;
                break;
            }
        }

        // Set the capacity
        tick.capacity = newCapacity;

        return tick;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getPreviousTick() public view override returns (Tick memory tick) {
        return _previousTick;
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
    function getTimeToExpiry() external view override returns (uint48) {
        return _timeToExpiry;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getRedemptionPeriod() external view override returns (uint48) {
        return _redemptionPeriod;
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

    // ========== ADMIN FUNCTIONS ========== //

    function _setAuctionParameters(uint256 target_, uint256 tickSize_, uint256 minPrice_) internal {
        // Tick size must be non-zero
        if (tickSize_ == 0) revert CDAuctioneer_InvalidParams("tick size");

        // Min price must be non-zero
        if (minPrice_ == 0) revert CDAuctioneer_InvalidParams("min price");

        // Target must be non-zero
        if (target_ == 0) revert CDAuctioneer_InvalidParams("target");

        _auctionParameters = AuctionParameters(target_, tickSize_, minPrice_);

        // Emit event
        emit AuctionParametersUpdated(target_, tickSize_, minPrice_);
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
        emit AuctionResult(_dayState.convertible, previousTarget_, _auctionResultsNextIndex);

        // Increment the index (or loop around)
        _auctionResultsNextIndex++;
        // Loop around if necessary
        if (_auctionResultsNextIndex >= _auctionTrackingPeriod) {
            _auctionResultsNextIndex = 0;
        }

        // Reset the day state
        _dayState = Day(uint48(block.timestamp), 0, 0);
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
    ///             - The caller does not have the ROLE_HEART role
    ///             - The new tick size is 0
    ///             - The new min price is 0
    ///             - The new target is 0
    function setAuctionParameters(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_
    ) external override onlyRole(ROLE_HEART) {
        uint256 previousTarget = _auctionParameters.target;

        _setAuctionParameters(target_, tickSize_, minPrice_);

        // The following can be done even if the contract is not active nor initialized, since activating/initializing will set the tick capacity and price

        // Set the tick size
        // This has the affect of resetting the tick size to the default
        // The tick size may have been adjusted for the previous day if the target was met
        _previousTick.tickSize = tickSize_;

        // Ensure that the tick capacity is not larger than the new tick size
        // Otherwise, excess OHM will be converted
        if (tickSize_ < _previousTick.capacity) {
            _previousTick.capacity = tickSize_;
        }

        // Ensure that the minimum price is enforced
        // Otherwise, OHM will be converted at a price lower than the minimum
        if (minPrice_ > _previousTick.price) {
            _previousTick.price = minPrice_;
        }

        // Store the auction results, if necessary
        _storeAuctionResults(previousTarget);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function will revert if:
    ///             - The caller does not have the ROLE_ADMIN role
    ///             - The new time to expiry is 0
    ///
    /// @param  newTime_ The new time to expiry
    function setTimeToExpiry(uint48 newTime_) public override onlyAdminRole {
        // Value must be non-zero
        if (newTime_ == 0) revert CDAuctioneer_InvalidParams("time to expiry");

        _timeToExpiry = newTime_;

        // Emit event
        emit TimeToExpiryUpdated(newTime_);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function will revert if:
    ///             - The caller does not have the ROLE_ADMIN role
    ///             - The new redemption period is 0
    ///
    /// @param  newRedemptionPeriod_ The new redemption period
    function setRedemptionPeriod(uint48 newRedemptionPeriod_) public override onlyAdminRole {
        // Value must be non-zero
        if (newRedemptionPeriod_ == 0) revert CDAuctioneer_InvalidParams("redemption period");

        _redemptionPeriod = newRedemptionPeriod_;

        // Emit event
        emit RedemptionPeriodUpdated(newRedemptionPeriod_);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function will revert if:
    ///             - The caller does not have the ROLE_ADMIN role
    ///             - The new tick step is < 100e2
    ///
    /// @param      newStep_    The new tick step
    function setTickStep(uint24 newStep_) public override onlyAdminRole {
        // Value must be more than 100e2
        if (newStep_ < ONE_HUNDRED_PERCENT) revert CDAuctioneer_InvalidParams("tick step");

        _tickStep = newStep_;

        // Emit event
        emit TickStepUpdated(newStep_);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function will revert if:
    ///             - The caller does not have the ROLE_ADMIN role
    ///             - The new auction tracking period is 0
    ///
    /// @param      days_    The new auction tracking period
    function setAuctionTrackingPeriod(uint8 days_) public override onlyAdminRole {
        // Value must be non-zero
        if (days_ == 0) revert CDAuctioneer_InvalidParams("auction tracking period");

        _auctionTrackingPeriod = days_;

        // Reset the auction results and index and set to the new length
        _auctionResults = new int256[](days_);
        _auctionResultsNextIndex = 0;

        // Emit event
        emit AuctionTrackingPeriodUpdated(days_);
    }

    // ========== ACTIVATION/DEACTIVATION ========== //

    /// @inheritdoc PolicyEnabler
    /// @dev        This function will revert if:
    ///             - The enable data is not the correct length
    ///             - The enable data is not an encoded `EnableParams` struct
    ///             - The auction parameters are invalid
    ///             - The tick step is invalid
    ///             - The time to expiry is invalid
    ///             - The redemption period is invalid
    ///             - The auction tracking period is invalid
    function _enable(bytes calldata enableData_) internal override {
        if (enableData_.length != _ENABLE_PARAMS_LENGTH)
            revert CDAuctioneer_InvalidParams("enable data");

        // Decode the enable data
        EnableParams memory params = abi.decode(enableData_, (EnableParams));

        // Set the auction parameters
        _setAuctionParameters(params.target, params.tickSize, params.minPrice);

        // Set the tick step
        setTickStep(params.tickStep);

        // Set the time to expiry
        setTimeToExpiry(params.timeToExpiry);

        // Set the redemption period
        setRedemptionPeriod(params.redemptionPeriod);

        // Set the auction tracking period
        setAuctionTrackingPeriod(params.auctionTrackingPeriod);

        // Initialize the current tick
        _previousTick.capacity = params.tickSize;
        _previousTick.price = params.minPrice;
        _previousTick.tickSize = params.tickSize;

        // Also set the lastUpdate to the current block timestamp
        // Otherwise, getCurrentTick() will calculate a long period of time having passed
        _previousTick.lastUpdate = uint48(block.timestamp);

        // Reset the day state
        _dayState = Day(uint48(block.timestamp), 0, 0);

        // Reset the auction results
        _auctionResults = new int256[](_auctionTrackingPeriod);
        _auctionResultsNextIndex = 0;
    }
}
