// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {RolesConsumer, ROLESv1} from "modules/ROLES/OlympusRoles.sol";

import {FullMath} from "libraries/FullMath.sol";

import {CDFacility} from "./CDFacility.sol";

interface CDRC20 {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function convertFor(uint256 amount) external view returns (uint256);

    function expiry() external view returns (uint256);
}

contract CDAuctioneer is Policy, RolesConsumer {
    using FullMath for uint256;

    // ========== DATA STRUCTURES ========== //

    struct State {
        uint256 target; // number of ohm per day
        uint256 tickSize; // number of ohm in a tick
        uint256 minPrice; // minimum tick price
        uint256 tickStep; // percentage increase (decrease) per tick
        uint256 timeToExpiry; // time between creation and expiry of deposit
        uint256 lastUpdate; // timestamp of last update to current tick
    }

    struct Day {
        uint256 deposits; // total deposited for day
        uint256 convertable; // total convertable for day
    }

    struct Tick {
        uint256 price;
        uint256 capacity;
    }

    // ========== EVENTS ========== //

    // ========== STATE VARIABLES ========== //

    Tick public currentTick;
    State public state;

    uint256 public decimals;

    CDFacility public cdFacility;

    mapping(uint256 => mapping(uint256 => address)) public cdTokens; // mapping(expiry => price => token)

    Day public today;

    // ========== SETUP ========== //

    constructor(Kernel kernel_) Policy(kernel_) {}

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

    /// @notice use a deposit to bid for CDs
    /// @param  deposit amount of reserve tokens
    /// @return convertable amount of convertable tokens
    function bid(uint256 deposit) external returns (uint256 convertable) {
        // update state
        currentTick = getCurrentTick();
        state.lastUpdate = block.timestamp;

        // iterate until user has no more reserves to bid
        while (deposit > 0) {
            // handle spent/capacity for tick
            uint256 amount = currentTick.capacity < convertFor(deposit, currentTick.price)
                ? state.tickSize
                : deposit;
            if (amount != state.tickSize) currentTick.capacity -= amount;
            else currentTick.price *= state.tickStep / decimals;

            // decrement bid and increment tick price
            deposit -= amount;
            convertable += convertFor(amount, currentTick.price);
        }

        today.deposits += deposit;
        today.convertable += convertable;

        // mint amount of CD token
        cdFacility.addNewCD(msg.sender, deposit, convertable, block.timestamp + state.timeToExpiry);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice get current tick info
    /// @dev    time passing changes tick info
    /// @return tick info in Tick struct
    function getCurrentTick() public view returns (Tick memory tick) {
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

    /// @notice get amount of cdOHM for a deposit at a tick price
    /// @return amount convertable
    function convertFor(uint256 deposit, uint256 price) public view returns (uint256) {
        return (deposit * decimals) / price;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice update auction parameters
    /// @dev    only callable by the auction admin
    /// @param  newTarget new target sale per day
    /// @param  newSize new size per tick
    /// @param  newMinPrice new minimum tick price
    function beat(
        uint256 newTarget,
        uint256 newSize,
        uint256 newMinPrice
    ) external onlyRole("CD_Auction_Admin") returns (uint256 remainder) {
        remainder = (state.target > today.convertable) ? state.target - today.convertable : 0;

        state = State(
            newTarget,
            newSize,
            newMinPrice,
            state.tickStep,
            state.timeToExpiry,
            state.lastUpdate
        );
    }

    /// @notice update time between creation and expiry of deposit
    /// @param  newTime number of seconds
    function setTimeToExpiry(uint256 newTime) external onlyRole("CD_Admin") {
        state.timeToExpiry = newTime;
    }

    /// @notice update change between ticks
    /// @param  newStep percentage in decimal terms
    function setTickStep(uint256 newStep) external onlyRole("CD_Admin") {
        state.tickStep = newStep;
    }
}
