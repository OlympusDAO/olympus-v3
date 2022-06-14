// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import {TransferHelper} from "../libraries/TransferHelper.sol";
import {FullMath} from "../libraries/FullMath.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Kernel, Module} from "../Kernel.sol";

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
        uint256 price;
    }

    struct Band {
        Line high;
        Line low;
        uint256 spread;
    }

    struct Side {
        bool active;
        uint48 lastActive;
        uint256 capacity;
        uint256 threshold;
        uint256 market;
        uint256 lastMarketCapacity;
    }

    struct Range {
        Side low;
        Side high;
        Band cushion;
        Band wall;
    }

    /* ========== STATE VARIABLES ========== */

    Range internal _range;
    uint256 public thresholdFactor;

    /// Constants
    uint256 public constant FACTOR_SCALE = 1e4;

    /// Tokens
    ERC20 public immutable ohm;
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

    function KEYCODE() public pure override returns (bytes5) {
        return "RANGE";
    }

    /* ========== POLICY FUNCTIONS ========== */

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

    function range() external view returns (Range memory) {
        return _range;
    }

    function capacity(bool high_) external view returns (uint256) {
        if (high_) {
            return _range.high.capacity;
        } else {
            return _range.low.capacity;
        }
    }

    function active(bool high_) external view returns (bool) {
        if (high_) {
            return _range.high.active;
        } else {
            return _range.low.active;
        }
    }

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

    function spread(bool wall_) external view returns (uint256) {
        if (wall_) {
            return _range.wall.spread;
        } else {
            return _range.cushion.spread;
        }
    }

    function market(bool high_) external view returns (uint256) {
        if (high_) {
            return _range.high.market;
        } else {
            return _range.low.market;
        }
    }

    function lastMarketCapacity(bool high_) external view returns (uint256) {
        if (high_) {
            return _range.high.lastMarketCapacity;
        } else {
            return _range.low.lastMarketCapacity;
        }
    }
}
