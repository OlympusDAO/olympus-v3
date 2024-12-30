// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {RolesConsumer, ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

import {FullMath} from "src/libraries/FullMath.sol";

import {CDFacility} from "./CDFacility.sol";

contract CDAuctioneer is IConvertibleDepositAuctioneer, Policy, RolesConsumer, ReentrancyGuard {
    using FullMath for uint256;

    // ========== STATE VARIABLES ========== //

    Tick public currentTick;
    State public state;

    // TODO set decimals, make internal?
    uint256 public decimals;
    uint8 internal constant _ohmDecimals = 9;

    CDFacility public cdFacility;

    Day public today;

    // ========== SETUP ========== //

    constructor(Kernel kernel_, address cdFacility_) Policy(kernel_) {
        if (cdFacility_ == address(0))
            revert CDAuctioneer_InvalidParams("CD Facility address cannot be 0");

        // TODO set decimals

        cdFacility = CDFacility(cdFacility_);
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[2] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {}

    // ========== AUCTION ========== //

    /// @inheritdoc IConvertibleDepositAuctioneer
    function bid(uint256 deposit) external override nonReentrant returns (uint256 ohmOut) {
        // TODO day state needs to be reset at the start of each day
        // if the block timestamp is the first in a new day (since lastUpdate), reset day state

        // Update state
        currentTick = getCurrentTick();
        state.lastUpdate = uint48(block.timestamp);

        // Get bid results
        uint256 currentTickCapacity;
        uint256 currentTickPrice;
        (currentTickCapacity, currentTickPrice, ohmOut) = _previewBid(deposit);

        // Update day state
        today.deposits += deposit;
        today.convertible += ohmOut;

        // Update current tick
        currentTick.capacity = currentTickCapacity;
        currentTick.price = currentTickPrice;

        // Calculate average price based on the total deposit and ohmOut
        // This is the number of deposit tokens per OHM token
        // TODO check rounding
        uint256 conversionPrice = (deposit * _ohmDecimals) / ohmOut;

        // Create the CD tokens and position
        cdFacility.create(
            msg.sender,
            deposit,
            conversionPrice,
            uint48(block.timestamp + state.timeToExpiry),
            false
        );

        // TODO add position id to return value

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
        uint256 deposit_
    )
        internal
        view
        returns (uint256 currentTickCapacity, uint256 currentTickPrice, uint256 ohmOut)
    {
        Tick memory tick = getCurrentTick();
        uint256 remainingDeposit = deposit_;

        while (remainingDeposit > 0) {
            // TODO what happens if there is a remaining deposit that cannot be converted? Needs an escape hatch
            // consider returning the remaining deposit as a value

            // Calculate the amount of OHM that can be converted
            // given tick capacity
            uint256 amount = tick.capacity < _convertFor(remainingDeposit, tick.price)
                ? state.tickSize
                : remainingDeposit;

            // Record updates to the deposit and OHM
            // These updates are done before the tick updates, otherwise the price/capacity will differ from the first calculation above
            remainingDeposit -= amount;
            ohmOut += _convertFor(amount, tick.price);

            // Decrement tick capacity if it is not the full tick size
            // Otherwise, increase the tick price
            if (amount != state.tickSize) tick.capacity -= amount;
            else tick.price *= state.tickStep / decimals;
        }

        return (tick.capacity, tick.price, ohmOut);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function previewBid(uint256 deposit) external view override returns (uint256 ohmOut) {
        (, , ohmOut) = _previewBid(deposit);

        return ohmOut;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getCurrentTick() public view override returns (Tick memory tick) {
        // find amount of time passed and new capacity to add
        uint256 timePassed = block.timestamp - state.lastUpdate;
        uint256 newCapacity = (state.target * timePassed) / 1 days;

        tick = currentTick;

        // decrement price while ticks are full
        while (tick.capacity + newCapacity > state.tickSize) {
            newCapacity -= state.tickSize;
            tick.price *= decimals / state.tickStep;

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
    }

    function _convertFor(uint256 deposit, uint256 price) internal view returns (uint256) {
        return (deposit * decimals) / price;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getState() external view override returns (State memory) {
        return state;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getDay() external view override returns (Day memory) {
        return today;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepositAuctioneer
    function setAuctionParameters(
        uint256 newTarget,
        uint256 newSize,
        uint256 newMinPrice
    ) external override onlyRole("CD_Auction_Admin") returns (uint256 remainder) {
        // TODO should this be newTarget instead of state.target?
        remainder = (state.target > today.convertible) ? state.target - today.convertible : 0;

        state = State(
            newTarget,
            newSize,
            newMinPrice,
            state.tickStep,
            state.lastUpdate,
            state.timeToExpiry
        );
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function setTimeToExpiry(uint48 newTime) external override onlyRole("CD_Admin") {
        state.timeToExpiry = newTime;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function setTickStep(uint256 newStep) external override onlyRole("CD_Admin") {
        state.tickStep = newStep;
    }
}
