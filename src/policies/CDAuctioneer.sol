// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Libraries
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades dependencies
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {RolesConsumer, ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";
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
contract CDAuctioneer is IConvertibleDepositAuctioneer, Policy, RolesConsumer, ReentrancyGuard {
    using FullMath for uint256;

    // ========== STATE VARIABLES ========== //

    /// @notice The role that can perform periodic actions, such as updating the auction parameters
    bytes32 public constant ROLE_HEART = "cd_emissionmanager";

    /// @notice The role that can perform administrative actions, such as changing parameters
    bytes32 public constant ROLE_ADMIN = "cd_admin";

    /// @notice The role that can perform emergency actions, such as shutting down the contract
    bytes32 public constant ROLE_EMERGENCY_SHUTDOWN = "emergency_shutdown";

    /// @notice Address of the CDEPO module
    CDEPOv1 public CDEPO;

    /// @notice Address of the token that is being bid
    /// @dev    This is populated by the `configureDependencies()` function
    address public bidToken;

    /// @notice Scale of the bid token
    /// @dev    This is populated by the `configureDependencies()` function
    uint256 public bidTokenScale;

    /// @notice Previous tick of the auction
    /// @dev    Use `getCurrentTick()` to recalculate and access the latest data
    Tick internal _previousTick;

    /// @notice Auction parameters
    /// @dev    These values should only be set through the `setAuctionParameters()` function
    AuctionParameters internal _auctionParameters;

    /// @notice Auction state for the day
    Day internal _dayState;

    /// @notice Scale of the OHM token
    uint256 internal constant _ohmScale = 1e9;

    /// @notice Address of the Convertible Deposit Facility
    CDFacility public cdFacility;

    /// @notice Whether the contract functionality has been activated
    bool public locallyActive;

    /// @notice Whether the contract has been initialized
    /// @dev    When the contract has been initialized, the following can be assumed:
    ///         - The auction parameters have been set
    ///         - The tick step has been set
    ///         - The time to expiry has been set
    ///         - The tick capacity and price have been set to the standard tick size and minimum price
    ///         - The last update has been set to the current block timestamp
    bool public initialized;

    /// @notice The tick step
    /// @dev    See `getTickStep()` for more information
    uint24 internal _tickStep;

    uint24 public constant ONE_HUNDRED_PERCENT = 100e2;

    /// @notice The number of seconds between creation and expiry of convertible deposits
    /// @dev    See `getTimeToExpiry()` for more information
    uint48 internal _timeToExpiry;

    /// @notice The index of the next auction result
    uint8 internal _auctionResultsNextIndex;

    /// @notice The number of days that auction results are tracked for
    uint8 internal _auctionTrackingPeriod;

    /// @notice The auction results, where a positive number indicates an over-subscription for the day.
    /// @dev    The length of this array is equal to the auction tracking period
    int256[] internal _auctionResults;

    // ========== SETUP ========== //

    constructor(address kernel_, address cdFacility_) Policy(Kernel(kernel_)) {
        if (cdFacility_ == address(0))
            revert CDAuctioneer_InvalidParams("CD Facility address cannot be 0");

        cdFacility = CDFacility(cdFacility_);

        // Disable functionality until initialized
        locallyActive = false;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("CDEPO");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        CDEPO = CDEPOv1(getModuleAddress(dependencies[1]));

        bidToken = address(CDEPO.ASSET());
        bidTokenScale = 10 ** ERC20(bidToken).decimals();
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
    ) external override nonReentrant onlyActive returns (uint256 ohmOut, uint256 positionId) {
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
        positionId = cdFacility.create(
            msg.sender,
            depositIn,
            conversionPrice,
            uint48(block.timestamp + _timeToExpiry),
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
    ///             - If the calculation is occurring on a new day, the tick size will reset to the standard
    ///             - Until the new capacity is <= to the tick size, reduce the capacity by the tick size and reduce the price by the tick step
    ///             - If the calculated price is ever lower than the minimum price, the new price is set to the minimum price and the capacity is set to the tick size
    function getCurrentTick() public view onlyActive returns (Tick memory tick) {
        // Find amount of time passed and new capacity to add
        uint256 timePassed = block.timestamp - _previousTick.lastUpdate;
        uint256 capacityToAdd = (_auctionParameters.target * timePassed) / 1 days;

        // Skip if the new capacity is 0
        if (capacityToAdd == 0) return _previousTick;

        tick = _previousTick;
        uint256 newCapacity = tick.capacity + capacityToAdd;

        // If the current date is on a different day to the last bid, the tick size will reset to the standard
        if (isDayComplete()) {
            tick.tickSize = _auctionParameters.tickSize;
        }

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

    /// @inheritdoc IConvertibleDepositAuctioneer
    function isDayComplete() public view override returns (bool) {
        return block.timestamp / 86400 > _dayState.initTimestamp / 86400;
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
        if (!locallyActive) return;

        // Skip if the day state was set on the same day
        if (!isDayComplete()) return;

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
    /// @dev        This function performs the following:
    ///             - Performs validation of the inputs
    ///             - Sets the auction parameters
    ///             - Adjusts the current tick capacity and price, if necessary
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
    function setTimeToExpiry(uint48 newTime_) public override onlyRole(ROLE_ADMIN) {
        // Value must be non-zero
        if (newTime_ == 0) revert CDAuctioneer_InvalidParams("time to expiry");

        _timeToExpiry = newTime_;

        // Emit event
        emit TimeToExpiryUpdated(newTime_);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function will revert if:
    ///             - The caller does not have the ROLE_ADMIN role
    ///             - The new tick step is < 100e2
    ///
    /// @param      newStep_    The new tick step
    function setTickStep(uint24 newStep_) public override onlyRole(ROLE_ADMIN) {
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
    function setAuctionTrackingPeriod(uint8 days_) public override onlyRole(ROLE_ADMIN) {
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

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function will revert if:
    ///             - The caller does not have the ROLE_ADMIN role
    ///             - The contract is already initialized
    ///             - The contract is already active
    ///             - Validation of the inputs fails
    ///
    ///             The outcome of running this function is that the contract will be in a valid state for bidding to take place.
    function initialize(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_,
        uint24 tickStep_,
        uint48 timeToExpiry_,
        uint8 auctionTrackingPeriod_
    ) external onlyRole(ROLE_ADMIN) {
        // If initialized, revert
        if (initialized) revert CDAuctioneer_InvalidState();

        // Set the auction parameters
        _setAuctionParameters(target_, tickSize_, minPrice_);

        // Set the tick step
        // This emits the event
        setTickStep(tickStep_);

        // Set the time to expiry
        // This emits the event
        setTimeToExpiry(timeToExpiry_);

        // Set the auction tracking period
        // This emits the event
        setAuctionTrackingPeriod(auctionTrackingPeriod_);

        // Initialize the current tick
        _previousTick.capacity = tickSize_;
        _previousTick.price = minPrice_;
        _previousTick.tickSize = tickSize_;

        // Set the initialized flag
        initialized = true;

        // Activate the contract
        // This emits the event
        _activate();
    }

    function _activate() internal {
        // If not initialized, revert
        if (!initialized) revert CDAuctioneer_NotInitialized();

        // If the contract is already active, revert
        if (locallyActive) revert CDAuctioneer_InvalidState();

        // Set the contract to active
        locallyActive = true;

        // Also set the lastUpdate to the current block timestamp
        // Otherwise, getCurrentTick() will calculate a long period of time having passed
        _previousTick.lastUpdate = uint48(block.timestamp);

        // Reset the day state
        _dayState = Day(uint48(block.timestamp), 0, 0);

        // Reset the auction results
        _auctionResults = new int256[](_auctionTrackingPeriod);
        _auctionResultsNextIndex = 0;

        // Emit event
        emit Activated();
    }

    /// @notice Activate the contract functionality
    /// @dev    This function will revert if:
    ///         - The caller does not have the ROLE_EMERGENCY_SHUTDOWN role
    ///         - The contract has not previously been initialized
    ///         - The contract is already active
    function activate() external onlyRole(ROLE_EMERGENCY_SHUTDOWN) {
        _activate();
    }

    /// @notice Deactivate the contract functionality
    /// @dev    This function will revert if:
    ///         - The caller does not have the ROLE_EMERGENCY_SHUTDOWN role
    ///         - The contract is already inactive
    function deactivate() external onlyRole(ROLE_EMERGENCY_SHUTDOWN) {
        // If the contract is already inactive, revert
        if (!locallyActive) revert CDAuctioneer_InvalidState();

        // Set the contract to inactive
        locallyActive = false;

        // Emit event
        emit Deactivated();
    }

    // ========== MODIFIERS ========== //

    modifier onlyActive() {
        if (!locallyActive) revert CDAuctioneer_NotActive();
        _;
    }
}
