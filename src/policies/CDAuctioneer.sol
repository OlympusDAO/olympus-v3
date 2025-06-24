// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Libraries
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";

// Bophades dependencies
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {CDFacility} from "src/policies/CDFacility.sol";

/// @title  Convertible Deposit Auctioneer
/// @notice Implementation of the {IConvertibleDepositAuctioneer} interface for a specific bid token and deposit period
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
contract CDAuctioneer is IConvertibleDepositAuctioneer, Policy, PolicyEnabler, ReentrancyGuard {
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

    // ========== STRUCTS ========== //

    struct DepositConfiguration {
        bool isConfigured;
        bool isEnabled;
    }

    struct BidOutput {
        uint256 tickCapacity;
        uint256 tickPrice;
        uint256 tickSize;
        uint256 depositIn;
        uint256 ohmOut;
    }

    struct BidParams {
        IERC20 depositAsset;
        uint8 depositPeriod;
        uint256 depositAmount;
        bool wrapPosition;
        bool wrapReceipt;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice Mapping between a deposit asset, deposit period and whether the configuration is enabled
    mapping(IERC20 depositAsset => mapping(uint8 depositPeriod => DepositConfiguration depositConfiguration))
        internal _depositConfigurations;
    // TODO consider using an EnumerableMap with a bytes32 key for the deposit asset and deposit period
    // This can probably also be a simple bool

    /// @notice Array of deposit assets
    EnumerableSet.AddressSet internal _depositAssets;

    /// @notice Array of deposit periods for an asset
    mapping(IERC20 depositAsset => EnumerableSet.UintSet depositPeriods)
        internal _depositAssetPeriods;

    /// @notice Previous tick of the auction
    /// @dev    Use `getCurrentTick()` to recalculate and access the latest data
    mapping(IERC20 depositAsset => mapping(uint8 depositPeriod => Tick previousTick))
        internal _depositAssetPreviousTicks;

    /// @notice Address of the Convertible Deposit Facility
    CDFacility public immutable CD_FACILITY;

    /// @notice Auction parameters
    /// @dev    These values should only be set through the `setAuctionParameters()` function
    AuctionParameters internal _auctionParameters;

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

    constructor(address kernel_, address cdFacility_) Policy(Kernel(kernel_)) {
        if (cdFacility_ == address(0)) revert CDAuctioneer_InvalidParams("cd facility");

        CD_FACILITY = CDFacility(cdFacility_);

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
    ///             - The calculated converted amount is 0
    function bid(
        IERC20 depositAsset_,
        uint8 depositPeriod_,
        uint256 depositAmount_,
        bool wrapPosition_,
        bool wrapReceipt_
    )
        external
        override
        nonReentrant
        onlyEnabled
        onlyDepositEnabled(depositAsset_, depositPeriod_)
        returns (uint256, uint256, uint256)
    {
        return
            _bid(
                BidParams({
                    depositAsset: depositAsset_,
                    depositPeriod: depositPeriod_,
                    depositAmount: depositAmount_,
                    wrapPosition: wrapPosition_,
                    wrapReceipt: wrapReceipt_
                })
            );
    }

    /// @notice Internal function to submit an auction bid on the given deposit asset and period
    /// @dev    This function expects the calling function to have already validated the contract state and deposit asset and period
    function _bid(BidParams memory params) internal returns (uint256, uint256, uint256) {
        uint256 ohmOut;
        uint256 depositIn;
        {
            // Get the current tick for the deposit asset and period
            Tick memory updatedTick = _getCurrentTick(params.depositAsset, params.depositPeriod);

            // Get bid results
            BidOutput memory output = _previewBid(params.depositAmount, updatedTick);

            // Reject if the OHM out is 0
            if (output.ohmOut == 0) revert CDAuctioneer_InvalidParams("converted amount");

            // Update state
            _dayState.convertible += output.ohmOut;

            // Update current tick
            updatedTick.price = output.tickPrice;
            updatedTick.capacity = output.tickCapacity;
            updatedTick.tickSize = output.tickSize;
            updatedTick.lastUpdate = uint48(block.timestamp);
            _depositAssetPreviousTicks[params.depositAsset][params.depositPeriod] = updatedTick;

            // Set values for the rest of the function
            ohmOut = output.ohmOut;
            depositIn = output.depositIn;
        }

        // Calculate average price based on the total deposit and ohmOut
        // This is the number of deposit tokens per OHM token
        // We round up to be conservative

        // Create the receipt tokens and position
        (uint256 positionId, uint256 receiptTokenId, ) = CD_FACILITY.createPosition(
            params.depositAsset,
            params.depositPeriod,
            msg.sender,
            depositIn,
            depositIn.mulDivUp(_ohmScale, ohmOut),
            params.wrapPosition,
            params.wrapReceipt
        );

        // Emit event
        emit Bid(
            msg.sender,
            address(params.depositAsset),
            params.depositPeriod,
            depositIn,
            ohmOut,
            positionId
        );

        return (ohmOut, positionId, receiptTokenId);
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
        output.tickSize = tick_.tickSize;

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
        IERC20 depositAsset_,
        uint8 depositPeriod_,
        uint256 bidAmount_
    )
        external
        view
        override
        onlyEnabled
        onlyDepositEnabled(depositAsset_, depositPeriod_)
        returns (uint256 ohmOut, address depositSpender)
    {
        // Get the updated tick based on the current state
        Tick memory currentTick = _getCurrentTick(depositAsset_, depositPeriod_);

        // Preview the bid results
        BidOutput memory output = _previewBid(bidAmount_, currentTick);
        ohmOut = output.ohmOut;

        return (ohmOut, address(CD_FACILITY.DEPOSIT_MANAGER()));
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

    function _getCurrentTick(
        IERC20 depositAsset_,
        uint8 depositPeriod_
    ) internal view returns (Tick memory tick) {
        // Find amount of time passed and new capacity to add
        uint256 newCapacity;
        {
            Tick memory previousTick = _depositAssetPreviousTicks[depositAsset_][depositPeriod_];
            uint256 timePassed = block.timestamp - previousTick.lastUpdate;
            uint256 capacityToAdd = (_auctionParameters.target * timePassed) / 1 days;

            // Skip if the new capacity is 0
            if (capacityToAdd == 0) return previousTick;

            tick = previousTick;
            newCapacity = tick.capacity + capacityToAdd;
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
    /// @dev        This function calculates the tick at the current time.
    ///
    ///             It uses the following approach:
    ///             - Calculate the added capacity based on the time passed since the last bid, and add it to the current capacity to get the new capacity
    ///             - Until the new capacity is <= to the tick size, reduce the capacity by the tick size and reduce the price by the tick step
    ///             - If the calculated price is ever lower than the minimum price, the new price is set to the minimum price and the capacity is set to the tick size
    ///
    ///             This function reverts if:
    ///             - The contract is not enabled
    ///             - The deposit asset and period are not enabled
    function getCurrentTick(
        IERC20 depositAsset_,
        uint8 depositPeriod_
    )
        external
        view
        onlyEnabled
        onlyDepositEnabled(depositAsset_, depositPeriod_)
        returns (Tick memory tick)
    {
        return _getCurrentTick(depositAsset_, depositPeriod_);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function returns the previous tick for the deposit asset and period
    ///             If the deposit asset and period are not configured, all values will be 0
    function getPreviousTick(
        IERC20 depositAsset_,
        uint8 depositPeriod_
    ) public view override returns (Tick memory tick) {
        return _depositAssetPreviousTicks[depositAsset_][depositPeriod_];
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
    function getDepositAssets() external view override returns (IERC20[] memory) {
        uint256 length = _depositAssets.length();
        IERC20[] memory assets = new IERC20[](length);
        for (uint256 i = 0; i < length; i++) {
            assets[i] = IERC20(_depositAssets.at(i));
        }

        return assets;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function getDepositPeriods(
        IERC20 depositAsset_
    ) external view override returns (uint8[] memory) {
        uint256 length = _depositAssetPeriods[depositAsset_].length();
        uint8[] memory periods = new uint8[](length);
        for (uint256 i = 0; i < length; i++) {
            periods[i] = uint8(_depositAssetPeriods[depositAsset_].at(i));
        }

        return periods;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function isDepositEnabled(
        IERC20 depositAsset_,
        uint8 depositPeriod_
    ) public view override returns (bool) {
        return _depositConfigurations[depositAsset_][depositPeriod_].isEnabled;
    }

    /// @notice Modifier to check if a deposit asset and period is enabled
    modifier onlyDepositEnabled(IERC20 depositAsset_, uint8 depositPeriod_) {
        if (!isDepositEnabled(depositAsset_, depositPeriod_)) {
            revert CDAuctioneer_DepositPeriodNotEnabled(address(depositAsset_), depositPeriod_);
        }
        _;
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    /// @dev        This function will revert if:
    ///             - The caller is not a manager or admin
    ///             - The deposit period is already enabled for this asset
    function enableDepositPeriod(
        IERC20 depositAsset_,
        uint8 depositPeriod_
    ) external override onlyManagerOrAdminRole {
        // Validate that the deposit asset and period is not already enabled
        if (_depositConfigurations[depositAsset_][depositPeriod_].isEnabled) {
            revert CDAuctioneer_DepositPeriodAlreadyEnabled(address(depositAsset_), depositPeriod_);
        }

        // Enable the deposit period
        _depositConfigurations[depositAsset_][depositPeriod_].isEnabled = true;

        // Add the deposit asset to the array if it is not already in it
        if (!_depositAssets.contains(address(depositAsset_))) {
            _depositAssets.add(address(depositAsset_));
        }

        // Add the deposit period to the array if it is not already in it
        if (!_depositAssetPeriods[depositAsset_].contains(depositPeriod_)) {
            _depositAssetPeriods[depositAsset_].add(depositPeriod_);
        }

        // Initialise the tick
        _depositAssetPreviousTicks[depositAsset_][depositPeriod_] = Tick(
            _auctionParameters.minPrice,
            _auctionParameters.tickSize,
            _auctionParameters.tickSize,
            uint48(block.timestamp)
        );

        // Emit event
        emit DepositPeriodEnabled(address(depositAsset_), depositPeriod_);
    }

    /// @inheritdoc IConvertibleDepositAuctioneer
    function disableDepositPeriod(
        IERC20 depositAsset_,
        uint8 depositPeriod_
    ) external override onlyManagerOrAdminRole {
        // Validate that the deposit asset and period is enabled
        if (!_depositConfigurations[depositAsset_][depositPeriod_].isEnabled) {
            revert CDAuctioneer_DepositPeriodNotEnabled(address(depositAsset_), depositPeriod_);
        }

        // Disable the deposit period
        _depositConfigurations[depositAsset_][depositPeriod_].isEnabled = false;

        // Remove the deposit period from the array
        _depositAssetPeriods[depositAsset_].remove(depositPeriod_);

        // Remove the deposit asset from the array if it is not enabled for any other periods
        if (_depositAssetPeriods[depositAsset_].length() == 0) {
            _depositAssets.remove(address(depositAsset_));
        }

        // Remove the tick
        delete _depositAssetPreviousTicks[depositAsset_][depositPeriod_];

        // Emit event
        emit DepositPeriodDisabled(address(depositAsset_), depositPeriod_);
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
        _dayState = Day(uint48(block.timestamp), 0);
    }

    function _updateTicks(
        uint256 tickSize_,
        uint256 minPrice_,
        bool enforceCapacity_,
        bool enforceMinPrice_,
        bool setLastUpdate_
    ) internal {
        // Iterate over assets
        uint256 assetLength = _depositAssets.length();
        for (uint256 i = 0; i < assetLength; i++) {
            IERC20 asset = IERC20(_depositAssets.at(i));

            // Iterate over periods
            uint256 periodLength = _depositAssetPeriods[asset].length();
            for (uint256 j = 0; j < periodLength; j++) {
                uint8 period = uint8(_depositAssetPeriods[asset].at(j));

                // Skip if the deposit period is not enabled
                if (!_depositConfigurations[asset][period].isEnabled) continue;

                // Get the previous tick
                Tick storage previousTick = _depositAssetPreviousTicks[asset][period];

                // Set the tick size
                // This has the affect of resetting the tick size to the default
                // The tick size may have been adjusted for the previous day if the target was met
                previousTick.tickSize = tickSize_;

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
    ///             - The new target is 0
    function setAuctionParameters(
        uint256 target_,
        uint256 tickSize_,
        uint256 minPrice_
    ) external override onlyRole(ROLE_EMISSION_MANAGER) {
        uint256 previousTarget = _auctionParameters.target;

        _setAuctionParameters(target_, tickSize_, minPrice_);

        // The following can be done even if the contract is not active nor initialized, since activating/initializing will set the tick capacity and price

        // Ensure all ticks are updated with the new parameters
        _updateTicks(tickSize_, minPrice_, false, false, false);

        // Store the auction results, if necessary
        _storeAuctionResults(previousTarget);
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

        // Set the auction tracking period
        setAuctionTrackingPeriod(params.auctionTrackingPeriod);

        // Ensure all ticks have the current parameters
        // Also set the lastUpdate to the current block timestamp
        // Otherwise, getCurrentTick() will calculate a long period of time having passed
        _updateTicks(params.tickSize, params.minPrice, true, true, true);

        // Reset the day state
        _dayState = Day(uint48(block.timestamp), 0);

        // Reset the auction results
        _auctionResults = new int256[](_auctionTrackingPeriod);
        _auctionResultsNextIndex = 0;
    }
}
