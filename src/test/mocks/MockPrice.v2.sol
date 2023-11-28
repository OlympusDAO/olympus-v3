// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "src/modules/PRICE/PRICE.v2.sol";

contract MockPrice is PRICEv2 {
    mapping(address => uint256) internal prices;
    mapping(address => uint256) internal movingAverages;
    mapping(address => uint256[]) internal observations;
    uint48 internal timestamp;

    constructor(Kernel kernel_, uint8 decimals_, uint32 observationFrequency_) Module(kernel_) {
        timestamp = uint48(block.timestamp);
        observationFrequency = observationFrequency_;
        decimals = decimals_;
    }

    // ========== KERNEL FUNCTIONS ========== //

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 2;
        minor = 0;
    }

    // ========== FUNCTIONS ========== //

    function setTimestamp(uint48 timestamp_) public {
        timestamp = timestamp_;
    }

    function setPrice(address asset, uint256 price) public {
        prices[asset] = price;
    }

    function setMovingAverage(address asset, uint256 movingAverage) public {
        movingAverages[asset] = movingAverage;
    }

    function setObservations(address asset, uint256[] memory observations_) public {
        observations[asset] = observations_;
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
        uint256 price;
        if (variant_ == Variant.CURRENT || variant_ == Variant.LAST) {
            price = prices[asset_];
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            price = movingAverages[asset_];
        } else {
            revert PRICE_ParamsVariantInvalid(variant_);
        }

        // Mimic PRICE's behaviour of reverting
        if (price == 0) {
            revert PRICE_PriceZero(asset_);
        }

        return (price, timestamp);
    }

    function getPriceIn(address asset_, address base_) external view override returns (uint256) {
        (uint256 price, ) = getPriceIn(asset_, base_, Variant.CURRENT);
        return price;
    }

    function getPriceIn(
        address asset_,
        address base_,
        uint48 maxAge_
    ) external view override returns (uint256) {
        (uint256 price, ) = getPriceIn(asset_, base_, Variant.CURRENT);
        return price;
    }

    function getPriceIn(
        address asset_,
        address base_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        uint256 assetPrice;
        uint256 basePrice;
        if (variant_ == Variant.CURRENT || variant_ == Variant.LAST) {
            assetPrice = prices[asset_];
            basePrice = prices[base_];
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            assetPrice = movingAverages[asset_];
            basePrice = movingAverages[base_];
        } else {
            revert PRICE_ParamsVariantInvalid(variant_);
        }

        if (assetPrice == 0) revert PRICE_PriceZero(asset_);
        if (basePrice == 0) revert PRICE_PriceZero(base_);

        // Return asset price / base price
        return ((assetPrice * 10 ** decimals) / basePrice, timestamp);
    }

    function setPriceDecimals(uint8 decimals_) public {
        decimals = decimals_;
    }

    // Required by interface, but not implemented
    function getAssets() external view override returns (address[] memory) {}

    function getAssetData(address asset_) external view override returns (Asset memory) {
        return
            Asset({
                approved: true,
                storeMovingAverage: true,
                useMovingAverage: false,
                movingAverageDuration: 30 days,
                nextObsIndex: 0,
                numObservations: 90,
                lastObservationTime: uint48(block.timestamp),
                cumulativeObs: 0,
                obs: observations[asset_],
                strategy: bytes(""),
                feeds: bytes("")
            });
    }

    function storePrice(address asset_) external override {
        getPrice(asset_, Variant.CURRENT);
    }

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
