// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "src/Kernel.sol";

abstract contract RANGEv1 is Module {
    // EVENTS
    event WallUp(bool high_, uint256 timestamp_, uint256 capacity_);
    event WallDown(bool high_, uint256 timestamp_, uint256 capacity_);
    event CushionUp(bool high_, uint256 timestamp_, uint256 capacity_);
    event CushionDown(bool high_, uint256 timestamp_);
    event PricesChanged(
        uint256 wallLowPrice_,
        uint256 cushionLowPrice_,
        uint256 cushionHighPrice_,
        uint256 wallHighPrice_
    );
    event SpreadsChanged(uint256 cushionSpread_, uint256 wallSpread_);
    event ThresholdFactorChanged(uint256 thresholdFactor_);

    // ERRORS
    error RANGE_InvalidParams();

    // DATA STRUCTURES
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
    }

    struct Range {
        Side low; // Data specific to the low side of the range
        Side high; // Data specific to the high side of the range
        Band cushion; // Data relevant to cushions on both sides of the range
        Band wall; // Data relevant to walls on both sides of the range
    }

    // STATE

    // Range data singleton. See range().
    Range internal _range;

    /// @notice Threshold factor for the change, a percent in 2 decimals (i.e. 1000 = 10%). Determines how much of the capacity must be spent before the side is taken down.
    /// @dev    A threshold is required so that a wall is not "active" with a capacity near zero, but unable to be depleted practically (dust).
    uint256 public thresholdFactor;

    /// @notice OHM token contract address
    ERC20 public ohm;

    /// @notice Reserve token contract address
    ERC20 public reserve;

    // FUNCTIONS
    function updateCapacity(bool high_, uint256 capacity_) external virtual;

    function updatePrices(uint256 movingAverage_) external virtual;

    function regenerate(bool high_, uint256 capacity_) external virtual;

    function updateMarket(
        bool high_,
        uint256 market_,
        uint256 marketCapacity_
    ) external virtual;

    function setSpreads(uint256 cushionSpread_, uint256 wallSpread_) external virtual;

    function setThresholdFactor(uint256 thresholdFactor_) external virtual;

    function range() external virtual returns (Range memory);

    function capacity(bool high_) external virtual returns (uint256);

    function active(bool high_) external virtual returns (bool);

    function price(bool wall_, bool high_) external virtual returns (uint256);

    function spread(bool wall_) external virtual returns (uint256);

    function market(bool high_) external virtual returns (uint256);

    function lastActive(bool high_) external virtual returns (uint256);
}
