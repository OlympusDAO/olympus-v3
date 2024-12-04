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

    struct Tick {
        uint256 price;
        uint256 capacity;
    }

    // ========== EVENTS ========== //

    // ========== STATE VARIABLES ========== //

    Tick public currentTick;
    uint256 public target; // number of ohm per day
    uint256 public tickSize; // number of ohm in a tick
    uint256 public tickStep; // percentage increase (decrease) per tick
    uint256 public lastUpdate; // timestamp of last update to current tick
    uint256 public currentExpiry; // current CD token expiry
    uint256 public timeBetweenExpiries; // time between CD token expiries
    uint256 public minPrice; // minimum tick price

    uint256 public decimals;

    CDFacility public cdFacility;

    mapping(uint256 => mapping(uint256 => address)) public cdTokens; // mapping(expiry => price => token)

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
    /// @param deposit amount of reserve tokens
    /// @return tokens CD tokens minted to user
    /// @return amounts amounts of CD tokens minted to user
    function bid(
        uint256 deposit
    ) external returns (CDRC20[] memory tokens, uint256[] memory amounts) {
        // update state
        currentTick = getCurrentTick();
        currentExpiry = getCurrentExpiry();
        lastUpdate = block.timestamp;

        uint256 i;

        // iterate until user has no more reserves to bid
        while (deposit > 0) {
            // get CD token for tick price
            CDRC20 token = CDRC20(tokenFor(currentTick.price));

            // handle spent/capacity for tick
            uint256 amount = currentTick.capacity < token.convertFor(deposit) ? tickSize : deposit;
            if (amount != tickSize) currentTick.capacity -= amount;

            // mint amount of CD token
            cdFacility.addNewCD(msg.sender, amount, token);

            // decrement bid and increment tick price
            deposit -= amount;
            currentTick.price *= tickStep / decimals;

            // add to return arrays
            tokens[i] = token;
            amounts[i] = token.convertFor(amount);
            ++i;
        }
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @notice create, or return address for existing, CD token
    /// @param price tick price of CD token
    /// @return token address of CD token
    function tokenFor(uint256 price) internal returns (address token) {
        token = cdTokens[currentExpiry][price];
        if (token == address(0)) {
            // new token
        }
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice get current tick info
    /// @dev time passing changes tick info
    /// @return tick info in Tick struct
    function getCurrentTick() public view returns (Tick memory tick) {
        // find amount of time passed and new capacity to add
        uint256 timePassed = block.timestamp - lastUpdate;
        uint256 newCapacity = (target * timePassed) / 1 days;

        tick = currentTick;

        // decrement price while ticks are full
        while (tick.capacity + newCapacity > tickSize) {
            newCapacity -= tickSize;
            tick.price *= decimals / tickStep;

            // tick price does not go below the minimum
            // tick capacity is full if the min price is exceeded
            if (tick.price < minPrice) {
                tick.price = minPrice;
                newCapacity = tickSize;
                break;
            }
        }

        // decrement capacity by remainder
        tick.capacity = newCapacity;
    }

    /// @notice get current new CD expiry
    /// @return expiry timestamp of expiration
    function getCurrentExpiry() public view returns (uint256 expiry) {
        uint256 nextExpiry = currentExpiry + timeBetweenExpiries;
        expiry = nextExpiry > block.timestamp ? currentExpiry : nextExpiry;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice update auction parameters
    /// @dev only callable by the auction admin
    /// @param newTarget new target sale per day
    /// @param newSize new size per tick
    /// @param newMinPrice new minimum tick price
    function beat(
        uint256 newTarget,
        uint256 newSize,
        uint256 newMinPrice
    ) external onlyRole("CD_Auction_Admin") {
        target = newTarget;
        tickSize = newSize;
        minPrice = newMinPrice;
    }

    /// @notice update time between new CD expiries
    /// @param newTime number of seconds between expiries
    function setTimeBetweenExpiries(uint256 newTime) external onlyRole("CD_Auction_Admin") {
        timeBetweenExpiries = newTime;
    }
}
