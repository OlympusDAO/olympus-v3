// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {RANGEv2} from "src/modules/RANGE/RANGE.v2.sol";
import "src/Kernel.sol";

/// @notice Olympus Range data storage module
/// @dev    The Olympus Range contract stores information about the Olympus Range market operations status.
///         It provides a standard interface for Range data, including range prices and capacities of each range side.
///         The data provided by this contract is used by the Olympus Range Operator to perform market operations.
///         The Olympus Range Data is updated each epoch by the Olympus Range Operator contract.
contract OlympusRange is RANGEv2 {
    uint256 public constant ONE_HUNDRED_PERCENT = 100e2;
    uint256 public constant ONE_PERCENT = 1e2;

    //============================================================================================//
    //                                        MODULE SETUP                                        //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        ERC20 ohm_,
        ERC20 reserve_,
        uint256 thresholdFactor_,
        uint256[2] memory lowSpreads_, // [cushion, wall]
        uint256[2] memory highSpreads_ // [cushion, wall]
    ) Module(kernel_) {
        // Validate parameters
        if (
            lowSpreads_[0] < ONE_PERCENT ||
            lowSpreads_[1] >= ONE_HUNDRED_PERCENT ||
            lowSpreads_[0] > lowSpreads_[1] ||
            highSpreads_[0] < ONE_PERCENT ||
            highSpreads_[0] > highSpreads_[1] ||
            thresholdFactor_ >= ONE_HUNDRED_PERCENT ||
            thresholdFactor_ < ONE_PERCENT
        ) revert RANGE_InvalidParams();

        _range = Range({
            low: Side({
                active: false,
                lastActive: uint48(block.timestamp),
                capacity: 0,
                threshold: 0,
                market: type(uint256).max,
                cushion: Line({price: 0, spread: lowSpreads_[0]}),
                wall: Line({price: 0, spread: lowSpreads_[1]})
            }),
            high: Side({
                active: false,
                lastActive: uint48(block.timestamp),
                capacity: 0,
                threshold: 0,
                market: type(uint256).max,
                cushion: Line({price: 0, spread: highSpreads_[0]}),
                wall: Line({price: 0, spread: highSpreads_[1]})
            })
        });

        thresholdFactor = thresholdFactor_;
        ohm = ohm_;
        reserve = reserve_;

        emit SpreadsChanged(false, lowSpreads_[0], lowSpreads_[1]);
        emit SpreadsChanged(true, highSpreads_[0], highSpreads_[1]);
        emit ThresholdFactorChanged(thresholdFactor_);
    }

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("RANGE");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @inheritdoc RANGEv2
    function updateCapacity(bool high_, uint256 capacity_) external override permissioned {
        if (high_) {
            // Update capacity
            _range.high.capacity = capacity_;

            // If the new capacity is below the threshold, deactivate the wall if they are currently active
            if (capacity_ < _range.high.threshold && _range.high.active) {
                // Set wall to inactive
                _range.high.active = false;
                _range.high.lastActive = uint48(block.timestamp);

                emit WallDown(true, block.timestamp, capacity_);
            }
        } else {
            // Update capacity
            _range.low.capacity = capacity_;

            // If the new capacity is below the threshold, deactivate the wall if they are currently active
            if (capacity_ < _range.low.threshold && _range.low.active) {
                // Set wall to inactive
                _range.low.active = false;
                _range.low.lastActive = uint48(block.timestamp);

                emit WallDown(false, block.timestamp, capacity_);
            }
        }
    }

    /// @inheritdoc RANGEv2
    function updatePrices(uint256 target_) external override permissioned {
        // Calculate new wall and cushion values from target and spreads
        _range.low.wall.price =
            (target_ * (ONE_HUNDRED_PERCENT - _range.low.wall.spread)) /
            ONE_HUNDRED_PERCENT;
        _range.low.cushion.price =
            (target_ * (ONE_HUNDRED_PERCENT - _range.low.cushion.spread)) /
            ONE_HUNDRED_PERCENT;
        _range.high.cushion.price =
            (target_ * (ONE_HUNDRED_PERCENT + _range.high.cushion.spread)) /
            ONE_HUNDRED_PERCENT;
        _range.high.wall.price =
            (target_ * (ONE_HUNDRED_PERCENT + _range.high.wall.spread)) /
            ONE_HUNDRED_PERCENT;

        emit PricesChanged(
            _range.low.wall.price,
            _range.low.cushion.price,
            _range.high.cushion.price,
            _range.high.wall.price
        );
    }

    /// @inheritdoc RANGEv2
    function regenerate(bool high_, uint256 capacity_) external override permissioned {
        uint256 threshold = (capacity_ * thresholdFactor) / ONE_HUNDRED_PERCENT;

        if (high_) {
            // Re-initialize the high side
            _range.high.active = true;
            _range.high.lastActive = uint48(block.timestamp);
            _range.high.capacity = capacity_;
            _range.high.threshold = threshold;
        } else {
            // Reinitialize the low side
            _range.low.active = true;
            _range.low.lastActive = uint48(block.timestamp);
            _range.low.capacity = capacity_;
            _range.low.threshold = threshold;
        }

        emit WallUp(high_, block.timestamp, capacity_);
    }

    /// @inheritdoc RANGEv2
    function updateMarket(
        bool high_,
        uint256 market_,
        uint256 marketCapacity_
    ) public override permissioned {
        // If market id is max uint256, then marketCapacity must be 0
        if (market_ == type(uint256).max && marketCapacity_ != 0) revert RANGE_InvalidParams();

        // Store updated state
        if (high_) {
            _range.high.market = market_;
        } else {
            _range.low.market = market_;
        }

        if (market_ == type(uint256).max) {
            emit CushionDown(high_, block.timestamp);
        } else {
            emit CushionUp(high_, block.timestamp, marketCapacity_);
        }
    }

    /// @inheritdoc RANGEv2
    function setSpreads(
        bool high_,
        uint256 cushionSpread_,
        uint256 wallSpread_
    ) external override permissioned {
        // Confirm spreads are within allowed values
        if (cushionSpread_ < ONE_PERCENT || cushionSpread_ > wallSpread_)
            revert RANGE_InvalidParams();

        if (high_) {
            // No upper limit on high side

            // Set spreads
            _range.high.wall.spread = wallSpread_;
            _range.high.cushion.spread = cushionSpread_;
        } else {
            // Confirm spreads are within allowed values
            if (wallSpread_ >= ONE_HUNDRED_PERCENT) revert RANGE_InvalidParams();

            // Set spreads
            _range.low.wall.spread = wallSpread_;
            _range.low.cushion.spread = cushionSpread_;
        }

        emit SpreadsChanged(high_, cushionSpread_, wallSpread_);
    }

    /// @inheritdoc RANGEv2
    function setThresholdFactor(uint256 thresholdFactor_) external override permissioned {
        if (thresholdFactor_ >= ONE_HUNDRED_PERCENT || thresholdFactor_ < ONE_PERCENT)
            revert RANGE_InvalidParams();
        thresholdFactor = thresholdFactor_;

        emit ThresholdFactorChanged(thresholdFactor_);
    }

    //============================================================================================//
    //                                      VIEW FUNCTIONS                                        //
    //============================================================================================//

    /// @inheritdoc RANGEv2
    function range() external view override returns (Range memory) {
        return _range;
    }

    /// @inheritdoc RANGEv2
    function capacity(bool high_) external view override returns (uint256) {
        if (high_) {
            return _range.high.capacity;
        } else {
            return _range.low.capacity;
        }
    }

    /// @inheritdoc RANGEv2
    function active(bool high_) external view override returns (bool) {
        if (high_) {
            return _range.high.active;
        } else {
            return _range.low.active;
        }
    }

    /// @inheritdoc RANGEv2
    function price(bool high_, bool wall_) external view override returns (uint256) {
        if (high_) {
            if (wall_) {
                return _range.high.wall.price;
            } else {
                return _range.high.cushion.price;
            }
        } else {
            if (wall_) {
                return _range.low.wall.price;
            } else {
                return _range.low.cushion.price;
            }
        }
    }

    /// @inheritdoc RANGEv2
    function spread(bool high_, bool wall_) external view override returns (uint256) {
        if (high_) {
            if (wall_) {
                return _range.high.wall.spread;
            } else {
                return _range.high.cushion.spread;
            }
        } else {
            if (wall_) {
                return _range.low.wall.spread;
            } else {
                return _range.low.cushion.spread;
            }
        }
    }

    /// @inheritdoc RANGEv2
    function market(bool high_) external view override returns (uint256) {
        if (high_) {
            return _range.high.market;
        } else {
            return _range.low.market;
        }
    }

    /// @inheritdoc RANGEv2
    function lastActive(bool high_) external view override returns (uint256) {
        if (high_) {
            return _range.high.lastActive;
        } else {
            return _range.low.lastActive;
        }
    }
}
