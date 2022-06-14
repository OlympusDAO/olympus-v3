// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import {TransferHelper} from "../libraries/TransferHelper.sol";
import {FullMath} from "../libraries/FullMath.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Kernel, Module} from "../Kernel.sol";

/// @title  Olympus Range Data
/// @notice Olympus Range Data (Module) Contract
/// @dev    The Olympus Range Data contract stores information about the Olympus Range market operations status.
///         It provides a standard interface for Range data, including range prices and capacities of each range side.
///         The data provided by this contract is used by the Olympus Range Operator to perform market operations.
///         The Olympus Range Data is updated each epoch by the Olympus Range Operator contract.
/// @author Oighty, Zeus
contract OlympusRange is Module {
    using TransferHelper for ERC20;
    using FullMath for uint256;

    /* ========== ERRORS =========== */

    error RANGE_InvalidParams();

    /* ========== EVENTS =========== */

    event WallUp(bool high, uint256 timestamp, uint256 capacity);
    event WallDown(bool high, uint256 timestamp);
    event CushionUp(bool high, uint256 timestamp, uint256 capacity);
    event CushionDown(bool high, uint256 timestamp);

    /* ========== STRUCTS =========== */

    struct Line {
        uint256 price; // Price for the specified level
    }

    struct Band {
        Line high; // Price of the high side of the band
        Line low; // Price of the low side of the band
        uint256 spread; // Spread of the band (increase/decrease from the moving average to set the band prices), percent with 2 decimal places (i.e. 1000 = 10% spread)
    }

    struct Side {
        bool active; // Whether or not the side is active (i.e. the Operator is performing market operations on this side, true = active, false = inactive)
        uint48 lastActive; // Unix timestamp when the side was last active (in seconds)
        uint256 capacity; // Amount of tokens that can be used to defend the side of the range. Specified in OHM tokens on the high side and Reserve tokens on the low side.
        uint256 threshold; // Amount of tokens under which the side is taken down. Specified in OHM tokens on the high side and Reserve tokens on the low side.
        uint256 market; // Market ID of the cushion bond market for the side. If no market is active, the market ID is set to max uint256 value.
        uint256 lastMarketCapacity; // Capacity of the side's market at the last update. Used to determine how much capacity the market sold since the last update.
    }

    struct Range {
        Side low; // Data specific to the low side of the range
        Side high; // Data specific to the high side of the range
        Band cushion; // Data relevant to cushions on both sides of the range
        Band wall; // Data relevant to walls on both sides of the range
    }

    /* ========== STATE VARIABLES ========== */

    /// Range data singleton. See range().
    Range internal _range;

    /// @notice Threshold factor for the change, a percent in 2 decimals (i.e. 1000 = 10%). Determines how much of the capacity must be spent before the side is taken down.
    /// @dev    A threshold is required so that a wall is not "active" with a capacity near zero, but unable to be depleted practically (dust).
    uint256 public thresholdFactor;

    /// Constants
    uint256 public constant FACTOR_SCALE = 1e4;

    /// Tokens
    /// @notice OHM token contract address
    ERC20 public immutable ohm;

    /// @notice Reserve token contract address
    ERC20 public immutable reserve;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        Kernel kernel_,
        ERC20[2] memory tokens_,
        uint256[3] memory rangeParams_ // [thresholdFactor, cushionSpread, wallSpread]
    ) Module(kernel_) {
        _range = Range({
            low: Side({
                active: false,
                lastActive: uint48(block.timestamp),
                capacity: 0,
                threshold: 0,
                market: type(uint256).max,
                lastMarketCapacity: 0
            }),
            high: Side({
                active: false,
                lastActive: uint48(block.timestamp),
                capacity: 0,
                threshold: 0,
                market: type(uint256).max,
                lastMarketCapacity: 0
            }),
            cushion: Band({
                low: Line({price: 0}),
                high: Line({price: 0}),
                spread: rangeParams_[1]
            }),
            wall: Band({
                low: Line({price: 0}),
                high: Line({price: 0}),
                spread: rangeParams_[2]
            })
        });

        thresholdFactor = rangeParams_[0];
        ohm = tokens_[0];
        reserve = tokens_[1];
    }

    /* ========== FRAMEWORK CONFIGURATION ========== */
    /// @inheritdoc Module
    function KEYCODE() public pure override returns (bytes5) {
        return "RANGE";
    }

    /* ========== POLICY FUNCTIONS ========== */
    /// @notice                 Update the capacity for a side of the range.
    /// @notice                 Access restricted to approved policies.
    /// @param high_            Specifies the side of the range to update capacity for (true = high side, false = low side).
    /// @param capacity_        Amount to set the capacity to (OHM tokens for high side, Reserve tokens for low side).
    /// @param marketCapacity_  Amount to set the market capacity to (OHM tokens for high side, Reserve tokens for low side).
    function updateCapacity(
        bool high_,
        uint256 capacity_,
        uint256 marketCapacity_
    ) external onlyPermittedPolicies {
        if (high_) {
            /// Update capacity and market capacity if they changed
            /// @dev the function is used by different modules which may not update both capacities at once
            /// checking if the values have changed saves potential SSTOREs
            if (_range.high.capacity != capacity_) {
                _range.high.capacity = capacity_;
            }
            if (_range.high.lastMarketCapacity != marketCapacity_) {
                _range.high.lastMarketCapacity = marketCapacity_;
            }

            /// If the new capacity is below the threshold, deactivate the cushion and wall if they are currently active
            if (capacity_ < _range.high.threshold && _range.high.active) {
                /// Set wall to inactive
                _range.high.active = false;
                _range.high.lastActive = uint48(block.timestamp);

                /// Set cushion to inactive
                updateMarket(true, type(uint256).max, 0);

                /// Emit event
                emit WallDown(true, block.timestamp);
            }
        } else {
            /// Update capacity and market capacity if they changed
            /// @dev the function is used by different modules which may not update both capacities at once
            /// checking if the values have changed saves potential SSTOREs
            if (_range.low.capacity != capacity_) {
                _range.low.capacity = capacity_;
            }
            if (_range.low.lastMarketCapacity != marketCapacity_) {
                _range.low.lastMarketCapacity = marketCapacity_;
            }

            /// If the new capacity is below the threshold, deactivate the cushion and wall if they are currently active
            if (capacity_ < _range.low.threshold && _range.low.active) {
                /// Set wall to inactive
                _range.low.active = false;
                _range.low.lastActive = uint48(block.timestamp);

                /// Set cushion to inactive
                updateMarket(false, type(uint256).max, 0);

                /// Emit event
                emit WallDown(false, block.timestamp);
            }
        }
    }

    /// @notice                 Update the prices for the low and high sides.
    /// @notice                 Access restricted to approved policies.
    /// @param movingAverage_   Current moving average price to set range prices from.
    function updatePrices(uint256 movingAverage_)
        external
        onlyPermittedPolicies
    {
        /// Cache the spreads
        uint256 wallSpread = _range.wall.spread;
        uint256 cushionSpread = _range.cushion.spread;

        /// Calculate new wall and cushion values from moving average and spread
        _range.wall.low.price =
            (movingAverage_ * (FACTOR_SCALE - wallSpread)) /
            FACTOR_SCALE;
        _range.wall.high.price =
            (movingAverage_ * (FACTOR_SCALE + wallSpread)) /
            FACTOR_SCALE;

        _range.cushion.low.price =
            (movingAverage_ * (FACTOR_SCALE - cushionSpread)) /
            FACTOR_SCALE;
        _range.cushion.high.price =
            (movingAverage_ * (FACTOR_SCALE + cushionSpread)) /
            FACTOR_SCALE;
    }

    /// @notice                 Regenerate a side of the range to a specific capacity.
    /// @notice                 Access restricted to approved policies.
    /// @param high_            Specifies the side of the range to regenerate (true = high side, false = low side).
    /// @param capacity_        Amount to set the capacity to (OHM tokens for high side, Reserve tokens for low side).
    function regenerate(bool high_, uint256 capacity_)
        external
        onlyPermittedPolicies
    {
        uint256 threshold = (capacity_ * thresholdFactor) / FACTOR_SCALE;

        if (high_) {
            /// Re-initialize the high side
            _range.high = Side({
                active: true,
                lastActive: uint48(block.timestamp),
                capacity: capacity_,
                threshold: threshold,
                market: type(uint256).max,
                lastMarketCapacity: 0
            });
        } else {
            /// Reinitialize the low side
            _range.low = Side({
                active: true,
                lastActive: uint48(block.timestamp),
                capacity: capacity_,
                threshold: threshold,
                market: type(uint256).max,
                lastMarketCapacity: 0
            });
        }

        emit WallUp(high_, block.timestamp, capacity_);
    }

    /// @notice                 Update the market ID and market capacity (cushion) for a side of the range.
    /// @notice                 Access restricted to approved policies.
    /// @param high_            Specifies the side of the range to update market for (true = high side, false = low side).
    /// @param market_          Market ID to set for the side.
    /// @param marketCapacity_  Amount to set the last market capacity to (OHM tokens for high side, Reserve tokens for low side).
    function updateMarket(
        bool high_,
        uint256 market_,
        uint256 marketCapacity_
    ) public onlyPermittedPolicies {
        /// If market id is max uint256, then marketCapacity must be 0
        if (market_ == type(uint256).max && marketCapacity_ != 0)
            revert RANGE_InvalidParams();

        /// Store updated state
        if (high_) {
            _range.high.market = market_;
            _range.high.lastMarketCapacity = marketCapacity_;
        } else {
            _range.low.market = market_;
            _range.low.lastMarketCapacity = marketCapacity_;
        }

        /// Emit events
        if (market_ == type(uint256).max) {
            emit CushionDown(high_, block.timestamp);
        } else {
            emit CushionUp(high_, block.timestamp, marketCapacity_);
        }
    }

    /// @notice                 Set the wall and cushion spreads.
    /// @notice                 Access restricted to approved policies.
    /// @param cushionSpread_   Percent spread to set the cushions at above/below the moving average, assumes 2 decimals (i.e. 1000 = 10%).
    /// @param wallSpread_      Percent spread to set the walls at above/below the moving average, assumes 2 decimals (i.e. 1000 = 10%).
    /// @dev The new spreads will not go into effect until the next time updatePrices() is called.
    function setSpreads(uint256 cushionSpread_, uint256 wallSpread_)
        external
        onlyPermittedPolicies
    {
        /// Confirm spreads are within allowed values
        if (
            wallSpread_ > 10000 ||
            wallSpread_ < 100 ||
            cushionSpread_ > 10000 ||
            cushionSpread_ < 100 ||
            cushionSpread_ > wallSpread_
        ) revert RANGE_InvalidParams();

        /// Set spreads
        _range.wall.spread = wallSpread_;
        _range.cushion.spread = cushionSpread_;
    }

    /// @notice                 Set the threshold factor for when a wall is considered "down".
    /// @notice                 Access restricted to approved policies.
    /// @param thresholdFactor_ Percent of capacity that the wall should close below, assumes 2 decimals (i.e. 1000 = 10%).
    /// @dev The new threshold factor will not go into effect until the next time regenerate() is called for each side of the wall.
    function setThresholdFactor(uint256 thresholdFactor_)
        external
        onlyPermittedPolicies
    {
        /// Confirm threshold factor is within allowed values
        if (thresholdFactor_ > 10000 || thresholdFactor_ < 100)
            revert RANGE_InvalidParams();

        /// Set threshold factor
        thresholdFactor = thresholdFactor_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Get the full Range data in a struct.
    function range() external view returns (Range memory) {
        return _range;
    }

    /// @notice         Get the capacity for a side of the range.
    /// @param high_    Specifies the side of the range to get capacity for (true = high side, false = low side).
    function capacity(bool high_) external view returns (uint256) {
        if (high_) {
            return _range.high.capacity;
        } else {
            return _range.low.capacity;
        }
    }

    /// @notice         Get the status of a side of the range (whether it is active or not).
    /// @param high_    Specifies the side of the range to get status for (true = high side, false = low side).
    function active(bool high_) external view returns (bool) {
        if (high_) {
            return _range.high.active;
        } else {
            return _range.low.active;
        }
    }

    /// @notice         Get the price for the wall or cushion for a side of the range.
    /// @param wall_    Specifies the band to get the price for (true = wall, false = cushion).
    /// @param high_    Specifies the side of the range to get the price for (true = high side, false = low side).
    function price(bool wall_, bool high_) external view returns (uint256) {
        if (wall_) {
            if (high_) {
                return _range.wall.high.price;
            } else {
                return _range.wall.low.price;
            }
        } else {
            if (high_) {
                return _range.cushion.high.price;
            } else {
                return _range.cushion.low.price;
            }
        }
    }

    /// @notice        Get the spread for the wall or cushion band.
    /// @param wall_   Specifies the band to get the spread for (true = wall, false = cushion).
    function spread(bool wall_) external view returns (uint256) {
        if (wall_) {
            return _range.wall.spread;
        } else {
            return _range.cushion.spread;
        }
    }

    /// @notice         Get the market ID for a side of the range.
    /// @param high_    Specifies the side of the range to get market for (true = high side, false = low side).
    function market(bool high_) external view returns (uint256) {
        if (high_) {
            return _range.high.market;
        } else {
            return _range.low.market;
        }
    }

    /// @notice         Get the last market capacity for a side of the range.
    /// @param high_    Specifies the side of the range to get last market capacity for (true = high side, false = low side).
    function lastMarketCapacity(bool high_) external view returns (uint256) {
        if (high_) {
            return _range.high.lastMarketCapacity;
        } else {
            return _range.low.lastMarketCapacity;
        }
    }
}
