// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {RANGE_V1} from "src/modules/RANGE/RANGE.V1.sol";
import "src/Kernel.sol";

/// @notice Olympus Range data storage module
/// @dev    The Olympus Range contract stores information about the Olympus Range market operations status.
///         It provides a standard interface for Range data, including range prices and capacities of each range side.
///         The data provided by this contract is used by the Olympus Range Operator to perform market operations.
///         The Olympus Range Data is updated each epoch by the Olympus Range Operator contract.
contract OlympusRange is RANGE_V1 {
    uint256 public constant ONE_HUNDRED_PERCENT = 100e2;
    uint256 public constant ONE_PERCENT = 1e2;

    /*//////////////////////////////////////////////////////////////
                            MODULE INTERFACE
    //////////////////////////////////////////////////////////////*/

    constructor(
        Kernel kernel_,
        ERC20 ohm_,
        ERC20 reserve_,
        uint256 thresholdFactor_,
        uint256 cushionSpread_,
        uint256 wallSpread_
    ) Module(kernel_) {
        // Validate parameters
        if (
            wallSpread_ >= ONE_HUNDRED_PERCENT ||
            wallSpread_ < ONE_PERCENT ||
            cushionSpread_ >= ONE_HUNDRED_PERCENT ||
            cushionSpread_ < ONE_PERCENT ||
            cushionSpread_ > wallSpread_ ||
            thresholdFactor_ >= ONE_HUNDRED_PERCENT ||
            thresholdFactor_ < ONE_PERCENT
        ) revert RANGE_InvalidParams();

        _range = Range({
            low: Side({
                active: false,
                lastActive: uint48(block.timestamp),
                capacity: 0,
                threshold: 0,
                market: type(uint256).max
            }),
            high: Side({
                active: false,
                lastActive: uint48(block.timestamp),
                capacity: 0,
                threshold: 0,
                market: type(uint256).max
            }),
            cushion: Band({low: Line({price: 0}), high: Line({price: 0}), spread: cushionSpread_}),
            wall: Band({low: Line({price: 0}), high: Line({price: 0}), spread: wallSpread_})
        });

        thresholdFactor = thresholdFactor_;
        ohm = ohm_;
        reserve = reserve_;

        emit SpreadsChanged(cushionSpread_, wallSpread_);
        emit ThresholdFactorChanged(thresholdFactor_);
    }

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("RANGE");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /*//////////////////////////////////////////////////////////////
                               CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Update the capacity for a side of the range.
    /// @notice Access restricted to activated policies.
    /// @param  high_ - Specifies the side of the range to update capacity for (true = high side, false = low side).
    /// @param  capacity_ - Amount to set the capacity to (OHM tokens for high side, Reserve tokens for low side).
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

    /// @notice Update the prices for the low and high sides.
    /// @notice Access restricted to activated policies.
    /// @param  movingAverage_ - Current moving average price to set range prices from.
    function updatePrices(uint256 movingAverage_) external override permissioned {
        // Cache the spreads
        uint256 wallSpread = _range.wall.spread;
        uint256 cushionSpread = _range.cushion.spread;

        // Calculate new wall and cushion values from moving average and spread
        _range.wall.low.price =
            (movingAverage_ * (ONE_HUNDRED_PERCENT - wallSpread)) /
            ONE_HUNDRED_PERCENT;
        _range.wall.high.price =
            (movingAverage_ * (ONE_HUNDRED_PERCENT + wallSpread)) /
            ONE_HUNDRED_PERCENT;

        _range.cushion.low.price =
            (movingAverage_ * (ONE_HUNDRED_PERCENT - cushionSpread)) /
            ONE_HUNDRED_PERCENT;
        _range.cushion.high.price =
            (movingAverage_ * (ONE_HUNDRED_PERCENT + cushionSpread)) /
            ONE_HUNDRED_PERCENT;

        emit PricesChanged(
            _range.wall.low.price,
            _range.cushion.low.price,
            _range.cushion.high.price,
            _range.wall.high.price
        );
    }

    /// @notice Regenerate a side of the range to a specific capacity.
    /// @notice Access restricted to activated policies.
    /// @param  high_ - Specifies the side of the range to regenerate (true = high side, false = low side).
    /// @param  capacity_ - Amount to set the capacity to (OHM tokens for high side, Reserve tokens for low side).
    function regenerate(bool high_, uint256 capacity_) external override permissioned {
        uint256 threshold = (capacity_ * thresholdFactor) / ONE_HUNDRED_PERCENT;

        if (high_) {
            // Re-initialize the high side
            _range.high = Side({
                active: true,
                lastActive: uint48(block.timestamp),
                capacity: capacity_,
                threshold: threshold,
                market: _range.high.market
            });
        } else {
            // Reinitialize the low side
            _range.low = Side({
                active: true,
                lastActive: uint48(block.timestamp),
                capacity: capacity_,
                threshold: threshold,
                market: _range.low.market
            });
        }

        emit WallUp(high_, block.timestamp, capacity_);
    }

    /// @notice Update the market ID (cushion) for a side of the range.
    /// @notice Access restricted to activated policies.
    /// @param  high_ - Specifies the side of the range to update market for (true = high side, false = low side).
    /// @param  market_ - Market ID to set for the side.
    /// @param  marketCapacity_ - Amount to set the last market capacity to (OHM tokens for high side, Reserve tokens for low side).
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

    /// @notice Set the wall and cushion spreads.
    /// @notice Access restricted to activated policies.
    /// @param  cushionSpread_ - Percent spread to set the cushions at above/below the moving average, assumes 2 decimals (i.e. 1000 = 10%).
    /// @param  wallSpread_ - Percent spread to set the walls at above/below the moving average, assumes 2 decimals (i.e. 1000 = 10%).
    /// @dev    The new spreads will not go into effect until the next time updatePrices() is called.
    function setSpreads(uint256 cushionSpread_, uint256 wallSpread_)
        external
        override
        permissioned
    {
        // Confirm spreads are within allowed values
        if (
            wallSpread_ >= ONE_HUNDRED_PERCENT ||
            wallSpread_ < ONE_PERCENT ||
            cushionSpread_ >= ONE_HUNDRED_PERCENT ||
            cushionSpread_ < ONE_PERCENT ||
            cushionSpread_ > wallSpread_
        ) revert RANGE_InvalidParams();

        // Set spreads
        _range.wall.spread = wallSpread_;
        _range.cushion.spread = cushionSpread_;

        emit SpreadsChanged(cushionSpread_, wallSpread_);
    }

    /// @notice Set the threshold factor for when a wall is considered "down".
    /// @notice Access restricted to activated policies.
    /// @param  thresholdFactor_ - Percent of capacity that the wall should close below, assumes 2 decimals (i.e. 1000 = 10%).
    /// @dev    The new threshold factor will not go into effect until the next time regenerate() is called for each side of the wall.
    function setThresholdFactor(uint256 thresholdFactor_) external override permissioned {
        if (thresholdFactor_ >= ONE_HUNDRED_PERCENT || thresholdFactor_ < ONE_PERCENT)
            revert RANGE_InvalidParams();
        thresholdFactor = thresholdFactor_;

        emit ThresholdFactorChanged(thresholdFactor_);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the full Range data in a struct.
    function range() external view override returns (Range memory) {
        return _range;
    }

    /// @notice Get the capacity for a side of the range.
    /// @param  high_ - Specifies the side of the range to get capacity for (true = high side, false = low side).
    function capacity(bool high_) external view override returns (uint256) {
        if (high_) {
            return _range.high.capacity;
        } else {
            return _range.low.capacity;
        }
    }

    /// @notice Get the status of a side of the range (whether it is active or not).
    /// @param  high_ - Specifies the side of the range to get status for (true = high side, false = low side).
    function active(bool high_) external view override returns (bool) {
        if (high_) {
            return _range.high.active;
        } else {
            return _range.low.active;
        }
    }

    /// @notice Get the price for the wall or cushion for a side of the range.
    /// @param  wall_ - Specifies the band to get the price for (true = wall, false = cushion).
    /// @param  high_ - Specifies the side of the range to get the price for (true = high side, false = low side).
    function price(bool wall_, bool high_) external view override returns (uint256) {
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

    /// @notice Get the spread for the wall or cushion band.
    /// @param  wall_ - Specifies the band to get the spread for (true = wall, false = cushion).
    function spread(bool wall_) external view override returns (uint256) {
        if (wall_) {
            return _range.wall.spread;
        } else {
            return _range.cushion.spread;
        }
    }

    /// @notice Get the market ID for a side of the range.
    /// @param  high_ - Specifies the side of the range to get market for (true = high side, false = low side).
    function market(bool high_) external view override returns (uint256) {
        if (high_) {
            return _range.high.market;
        } else {
            return _range.low.market;
        }
    }

    /// @notice Get the timestamp when the range was last active.
    /// @param  high_ - Specifies the side of the range to get timestamp for (true = high side, false = low side).
    function lastActive(bool high_) external view override returns (uint256) {
        if (high_) {
            return _range.high.lastActive;
        } else {
            return _range.low.lastActive;
        }
    }
}
