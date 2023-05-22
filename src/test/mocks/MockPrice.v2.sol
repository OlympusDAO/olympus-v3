// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "src/modules/PRICE/PRICE.v2.sol";

contract MockPricev2 is PRICEv2 {
    mapping(address => uint256) internal prices;
    uint48 internal timestamp;

    constructor(Kernel kernel_) Module(kernel_) {}

    function setTimestamp(uint48 timestamp_) public {
        timestamp = timestamp_;
    }

    function setPrice(address asset, uint256 price) public {
        prices[asset] = price;
    }

    function getPrice(address asset_) external view override returns (uint256) {
        (uint256 price, ) = getPrice(asset_, Variant.CURRENT);
        return price;
    }

    function getPrice(address asset_, uint48 maxAge_) external view override returns (uint256) {
        (uint256 price, ) = getPrice(asset_, Variant.CURRENT);
        return price;
    }

    function getPrice(
        address asset_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        uint256 price = prices[asset_];

        // Mimic PRICE's behaviour of reverting
        if (price == 0) {
            revert PRICE_PriceZero(asset_);
        }
        return (price, timestamp);
    }

    function getPriceIn(address asset_, address base_) external view override returns (uint256) {
        // Get asset price
        uint256 assetPrice = prices[asset_];

        // Get base price
        uint256 basePrice = prices[base_];

        // Return asset price / base price
        return (assetPrice * priceDecimals) / basePrice;
    }

    function getPriceIn(
        address asset_,
        address base_,
        uint48 maxAge_
    ) external view override returns (uint256) {
        // Get asset price
        uint256 assetPrice = prices[asset_];

        // Get base price
        uint256 basePrice = prices[base_];

        // Return asset price / base price
        return (assetPrice * priceDecimals) / basePrice;
    }

    function getPriceIn(
        address asset_,
        address base_,
        Variant variant_
    ) external view override returns (uint256, uint48) {
        // Get asset price
        uint256 assetPrice = prices[asset_];

        // Get base price
        uint256 basePrice = prices[base_];

        // Return asset price / base price
        return ((assetPrice * priceDecimals) / basePrice, timestamp);
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    function setPriceDecimals(uint8 decimals_) public {
        priceDecimals = decimals_;
    }

    // Required by interface, but not implemented
    function getAssets() external view override returns (address[] memory) {}

    function getAssetData(address asset_) external view override returns (Asset memory) {}

    function storePrice(address asset_) external override {}

    function addAsset(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        Component memory strategy_,
        Component[] memory feeds_
    ) external override {}

    function removeAsset(address asset_) external override {}

    function updateAssetPriceFeeds(address asset_, Component[] memory feeds_) external override {}

    function updateAssetPriceStrategy(
        address asset_,
        Component memory strategy_,
        bool useMovingAverage_
    ) external override {}

    function updateAssetMovingAverage(
        address asset_,
        bool storeMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external override {}
}
