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
    bytes32 public constant ROLE_HEART = "heart";

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

    /// @notice Current state of the auction
    State internal state;

    /// @notice Auction state at the time of the last bid (`state.lastUpdate`)
    Day internal dayState;

    /// @notice Scale of the OHM token
    uint256 internal constant _ohmScale = 1e9;

    /// @notice Address of the Convertible Deposit Facility
    CDFacility public cdFacility;

    /// @notice Whether the contract functionality has been activated
    bool public locallyActive;

    /// @notice The tick step
    /// @dev    See `getTickStep()` for more information
    uint24 internal _tickStep;

    uint24 public constant ONE_HUNDRED_PERCENT = 100e2;

    /// @notice The number of seconds between creation and expiry of convertible deposits
    /// @dev    See `getTimeToExpiry()` for more information
    uint48 internal _timeToExpiry;

    // TODO rename state to parameters

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

        bidToken = address(CDEPO.asset());
        bidTokenScale = 10 ** ERC20(bidToken).decimals();
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {}

    // ========== AUCTION ========== //

    /// @inheritdoc IConvertibleDepositAuctioneer
    // TODO document approach
    function bid(
        uint256 deposit
    ) external override nonReentrant onlyActive returns (uint256 ohmOut) {
        // Update the current tick based on the current state
        // lastUpdate is updated after this, otherwise time calculations will be incorrect
        _previousTick = getCurrentTick();

        // Get bid results
        uint256 currentTickCapacity;
        uint256 currentTickPrice;
        (currentTickCapacity, currentTickPrice, ohmOut) = _previewBid(deposit, _previousTick);

        // Reset the day state if this is the first bid of the day
        if (block.timestamp / 86400 > state.lastUpdate / 86400) {
            dayState = Day(0, 0);
        }

        // Update state
        state.lastUpdate = uint48(block.timestamp);
        dayState.deposits += deposit;
        dayState.convertible += ohmOut;

        // Update current tick
        _previousTick.capacity = currentTickCapacity;
        _previousTick.price = currentTickPrice;

        // Calculate average price based on the total deposit and ohmOut
        // This is the number of deposit tokens per OHM token
        // We round up to be conservative
        uint256 conversionPrice = deposit.mulDivUp(_ohmScale, ohmOut);

        // Create the CD tokens and position
        // The position ID is emitted as an event, so doesn't need to be returned
        cdFacility.create(
            msg.sender,
            deposit,
            conversionPrice,
            uint48(block.timestamp + _timeToExpiry),
            false
        );

        return ohmOut;
    }

    /// @notice Internal function to preview the quantity of OHM tokens that can be purchased for a given deposit amount
    /// @dev    The function also returns the adjusted capacity and price of the current tick
    ///
    /// @param  deposit_            The amount of deposit to be bid
    /// @return currentTickCapacity The adjusted capacity of the current tick
    /// @return currentTickPrice    The adjusted price of the current tick
    /// @return ohmOut              The quantity of OHM tokens that can be purchased
    function _previewBid(
        uint256 deposit_,
        Tick memory tick_
    )
        internal
        view
        returns (uint256 currentTickCapacity, uint256 currentTickPrice, uint256 ohmOut)
    {
        uint256 remainingDeposit = deposit_;
        currentTickCapacity = tick_.capacity;
        currentTickPrice = tick_.price;

        while (remainingDeposit > 0) {
            // TODO what happens if there is a remaining deposit that cannot be converted? Needs an escape hatch
            // consider returning the remaining deposit as a value

            // TODO what if the target is reached?

            uint256 depositAmount = remainingDeposit;
            uint256 convertibleAmount = _getConvertedDeposit(remainingDeposit, currentTickPrice);

            // If there is not enough capacity in the current tick, use the remaining capacity
            if (currentTickCapacity < convertibleAmount) {
                convertibleAmount = currentTickCapacity;
                // Convertible = deposit * OHM scale / price, so this is the inverse
                depositAmount = convertibleAmount.mulDiv(currentTickPrice, _ohmScale);

                // The tick has also been depleted, so update the price
                currentTickPrice = _getNewTickPrice(currentTickPrice, _tickStep);
                currentTickCapacity = state.tickSize;
            }
            // Otherwise, the tick has enough capacity and needs to be updated
            else {
                currentTickCapacity -= convertibleAmount;
            }

            // Record updates to the deposit and OHM
            remainingDeposit -= depositAmount;
            ohmOut += convertibleAmount;
        }

        return (currentTickCapacity, currentTickPrice, ohmOut);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function previewBid(
        uint256 bidAmount_
    ) external view override returns (uint256 ohmOut, address depositSpender) {
        // Get the updated tick based on the current state
        Tick memory currentTick = getCurrentTick();

        // Preview the bid results
        (, , ohmOut) = _previewBid(bidAmount_, currentTick);

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
    ) internal view returns (uint256 convertibleAmount) {
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
    ) internal view returns (uint256 newPrice) {
        newPrice = currentPrice_.mulDivUp(tickStep_, ONE_HUNDRED_PERCENT);
        return newPrice;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    ///
    /// @return tick    The updated tick
    function getCurrentTick() public view onlyActive returns (Tick memory tick) {
        // TODO document approach
        // find amount of time passed and new capacity to add
        uint256 timePassed = block.timestamp - state.lastUpdate;
        uint256 capacityToAdd = (state.target * timePassed) / 1 days;

        // Skip if the new capacity is 0
        if (capacityToAdd == 0) return _previousTick;

        tick = _previousTick;
        uint256 newCapacity = tick.capacity + capacityToAdd;


        // Iterate over the ticks until the capacity is within the tick size
        // This is the opposite of what happens in the bid function
        while (newCapacity > state.tickSize) {
            // Reduce the capacity by the tick size
            newCapacity -= state.tickSize;

            // Adjust the tick price by the tick step, in the opposite direction to the bid function
            tick.price = tick.price.mulDivUp(ONE_HUNDRED_PERCENT, _tickStep);

            // tick price does not go below the minimum
            // tick capacity is full if the min price is exceeded
            if (tick.price < state.minPrice) {
                tick.price = state.minPrice;
                newCapacity = state.tickSize;
                break;
            }
        }

        // decrement capacity by remainder
        tick.capacity = newCapacity;

        return tick;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getPreviousTick() public view override returns (Tick memory tick) {
        return _previousTick;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getState() external view override returns (State memory) {
        return state;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function returns the day state at the time of the last bid (`state.lastUpdate`)
    function getDayState() external view override returns (Day memory) {
        return dayState;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getTickStep() external view override returns (uint24) {
        return _tickStep;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getTimeToExpiry() external view override returns (uint48) {
        return _timeToExpiry;
    }

    // ========== ADMIN FUNCTIONS ========== //

    function _setAuctionParameters(uint256 target_, uint256 tickSize_, uint256 minPrice_) internal {
        // Tick size must be non-zero
        if (tickSize_ == 0) revert CDAuctioneer_InvalidParams("tick size");

        // Min price must be non-zero
        if (minPrice_ == 0) revert CDAuctioneer_InvalidParams("min price");

        state = State(target_, tickSize_, minPrice_, state.lastUpdate);

        // Emit event
        emit AuctionParametersUpdated(target_, tickSize_, minPrice_);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function performs the following:
    ///             - TODO
    ///
    ///             This function reverts if:
    ///             - The caller does not have the ROLE_HEART role
    ///             - The new tick size is 0
    ///             - The new min price is 0
    function setAuctionParameters(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_
    ) external override onlyRole(ROLE_HEART) returns (uint256 remainder) {
        // TODO should this be newTarget instead of state.target?
        // TODO Should the newTarget - dayState.convertible be used instead?
        // TODO how to handle if deactivated?
        // remainder = (state.target > dayState.convertible) ? state.target - dayState.convertible : 0;
        // TODO handling remainder moving average

        _setAuctionParameters(target_, tickSize_, minPrice_);

        return remainder;
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
    ///             - The contract is already active
    ///             - Validation of the inputs fails
    ///
    ///             The outcome of running this function is that the contract will be in a valid state for bidding to take place.
    function initialize(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_,
        uint24 tickStep_,
        uint48 timeToExpiry_
    ) external onlyRole(ROLE_ADMIN) {
        // If active, revert
        if (locallyActive) revert CDAuctioneer_InvalidState();

        // Set the auction parameters
        _setAuctionParameters(target_, tickSize_, minPrice_);

        // Set the tick step
        // This emits the event
        setTickStep(tickStep_);

        // Set the time to expiry
        // This emits the event
        setTimeToExpiry(timeToExpiry_);

        // Initialize the current tick
        _previousTick.capacity = tickSize_;
        _previousTick.price = minPrice_;

        // Activate the contract
        // This emits the event
        _activate();
    }

    function _activate() internal {
        // If these variables have not been set, then the contract has not previously been initialized
        if (_tickStep == 0 || _timeToExpiry == 0 || state.tickSize == 0 || state.minPrice == 0)
            revert CDAuctioneer_NotInitialized();

        // If the contract is already active, do nothing
        if (locallyActive) return;

        // Set the contract to active
        locallyActive = true;

        // Also set the lastUpdate to the current block timestamp
        // Otherwise, getCurrentTick() will calculate a long period of time having passed
        state.lastUpdate = uint48(block.timestamp);

        // Emit event
        emit Activated();
    }

    /// @notice Activate the contract functionality
    /// @dev    This function will revert if:
    ///         - The caller does not have the ROLE_EMERGENCY_SHUTDOWN role
    ///         - The contract has not previously been initialized
    ///
    ///         Note that if the contract is already active, this function will do nothing.
    function activate() external onlyRole(ROLE_EMERGENCY_SHUTDOWN) {
        _activate();
    }

    /// @notice Deactivate the contract functionality
    /// @dev    This function will revert if:
    ///         - The caller does not have the ROLE_EMERGENCY_SHUTDOWN role
    ///
    ///         Note that if the contract is already inactive, this function will do nothing.
    function deactivate() external onlyRole(ROLE_EMERGENCY_SHUTDOWN) {
        // If the contract is already inactive, do nothing
        if (!locallyActive) return;

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
