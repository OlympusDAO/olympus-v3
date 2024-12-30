// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {RolesConsumer, ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {FullMath} from "src/libraries/FullMath.sol";

import {CDFacility} from "./CDFacility.sol";

/// @title  Convertible Deposit Auctioneer
/// @notice Implementation of the IConvertibleDepositAuctioneer interface
/// @dev    This contract requires the "cd_admin" role to be assigned to an admin account.
contract CDAuctioneer is IConvertibleDepositAuctioneer, Policy, RolesConsumer, ReentrancyGuard {
    using FullMath for uint256;

    // ========== STATE VARIABLES ========== //

    /// @notice Address of the CDEPO module
    CDEPOv1 public CDEPO;

    /// @notice Address of the token that is being bid
    /// @dev    This is populated by the `configureDependencies()` function
    address public bidToken;

    /// @notice Scale of the bid token
    /// @dev    This is populated by the `configureDependencies()` function
    uint256 public bidTokenScale;

    /// @notice Current tick of the auction
    /// @dev    Use `getCurrentTick()` to recalculate and access the latest data
    Tick internal currentTick;

    /// @notice Current state of the auction
    State internal state;

    /// @notice Auction state at the time of the last bid (`state.lastUpdate`)
    Day internal dayState;

    /// @notice Scale of the OHM token
    uint256 internal constant _ohmScale = 10 ** 9;

    /// @notice Address of the Convertible Deposit Facility
    CDFacility public cdFacility;

    /// @notice Whether the contract functionality has been activated
    bool public locallyActive;

    // ========== SETUP ========== //

    constructor(Kernel kernel_, address cdFacility_) Policy(kernel_) {
        if (cdFacility_ == address(0))
            revert CDAuctioneer_InvalidParams("CD Facility address cannot be 0");

        cdFacility = CDFacility(cdFacility_);

        // Disable functionality until activated
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
    function bid(uint256 deposit) external override nonReentrant returns (uint256 ohmOut) {
        // Update the current tick based on the current state
        // lastUpdate is updated after this, otherwise time calculations will be incorrect
        currentTick = _getUpdatedTick();

        // Get bid results
        uint256 currentTickCapacity;
        uint256 currentTickPrice;
        (currentTickCapacity, currentTickPrice, ohmOut) = _previewBid(deposit, currentTick);

        // Reset the day state if this is the first bid of the day
        if (block.timestamp / 86400 > state.lastUpdate / 86400) {
            dayState = Day(0, 0);
        }

        // Update state
        state.lastUpdate = uint48(block.timestamp);
        dayState.deposits += deposit;
        dayState.convertible += ohmOut;

        // Update current tick
        currentTick.capacity = currentTickCapacity;
        currentTick.price = currentTickPrice;

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
            uint48(block.timestamp + state.timeToExpiry),
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

            uint256 depositAmount = remainingDeposit;
            uint256 convertibleAmount = _convertFor(remainingDeposit, currentTickPrice);

            // If there is not enough capacity in the current tick, use the remaining capacity
            if (currentTickCapacity < convertibleAmount) {
                convertibleAmount = currentTickCapacity;
                depositAmount = _convertFor(convertibleAmount, currentTickPrice);

                // The tick has also been depleted, so update the price
                currentTickPrice = currentTickPrice.mulDivUp(state.tickStep, bidTokenScale);
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
        Tick memory updatedTick = _getUpdatedTick();

        // Preview the bid results
        (, , ohmOut) = _previewBid(bidAmount_, updatedTick);

        return (ohmOut, address(CDEPO));
    }

    // ========== VIEW FUNCTIONS ========== //

    function _convertFor(uint256 deposit, uint256 price) internal view returns (uint256) {
        return deposit.mulDiv(bidTokenScale, price);
    }

    /// @notice Calculates an updated tick based on the current state
    ///
    /// @return tick    The updated tick
    function _getUpdatedTick() internal view returns (Tick memory tick) {
        // find amount of time passed and new capacity to add
        uint256 timePassed = block.timestamp - state.lastUpdate;
        uint256 newCapacity = (state.target * timePassed) / 1 days;

        tick = currentTick;

        // decrement price while ticks are full
        while (tick.capacity + newCapacity > state.tickSize) {
            newCapacity -= state.tickSize;
            tick.price *= bidTokenScale / state.tickStep;

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
    function getCurrentTick() public view override returns (Tick memory tick) {
        return currentTick;
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

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepositAuctioneer
    function setAuctionParameters(
        uint256 newTarget,
        uint256 newSize,
        uint256 newMinPrice
    ) external override onlyRole("cd_admin") returns (uint256 remainder) {
        // TODO should this be newTarget instead of state.target?
        // TODO Should the newTarget - dayState.convertible be used instead?
        remainder = (state.target > dayState.convertible) ? state.target - dayState.convertible : 0;

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
    function setTimeToExpiry(uint48 newTime) external override onlyRole("cd_admin") {
        state.timeToExpiry = newTime;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function setTickStep(uint256 newStep) external override onlyRole("cd_admin") {
        state.tickStep = newStep;
    }

    /// @notice Activate the contract functionality
    /// @dev    This function is only callable by the "cd_admin" role
    function activate() external onlyRole("cd_admin") {
        locallyActive = true;
    }

    /// @notice Deactivate the contract functionality
    /// @dev    This function is only callable by the "cd_admin" role
    function deactivate() external onlyRole("cd_admin") {
        locallyActive = false;
    }
}
