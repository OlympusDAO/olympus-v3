// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function)
pragma solidity ^0.8.15;

import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";

contract MockPrice is PRICEv2 {
    mapping(address => bool) internal assetApproved;
    mapping(address => uint256) internal prices;
    mapping(address => uint256) internal movingAverages;
    mapping(address => uint256[]) internal observations;
    mapping(address => uint256) internal lastStoredPrices;
    mapping(address => uint48) internal lastStoredTimestamps;
    uint48 internal timestamp;

    address[] internal _assets;

    constructor(Kernel kernel_, uint8 decimals_, uint32 observationFrequency_) Module(kernel_) {
        timestamp = uint48(block.timestamp);
        _observationFrequency = observationFrequency_;
        _decimals = decimals_;
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
        assetApproved[asset] = true;
        prices[asset] = price;

        // Add to the assets array
        bool exists = false;
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_assets[i] == asset) {
                exists = true;
                break;
            }
        }

        if (!exists) {
            _assets.push(asset);
        }
    }

    function setMovingAverage(address asset, uint256 movingAverage) public {
        movingAverages[asset] = movingAverage;
    }

    /// @notice Test helper to directly set LAST cache payload.
    /// @dev    Used to simulate edge cases such as a zero timestamp with non-zero price.
    function setLastPrice(address asset_, uint256 price_, uint48 timestamp_) public {
        assetApproved[asset_] = true;
        lastStoredPrices[asset_] = price_;
        lastStoredTimestamps[asset_] = timestamp_;
    }

    function setObservations(address asset, uint256[] memory observations_) public {
        observations[asset] = observations_;
    }

    function getPrice(address asset_) external view override returns (uint256) {
        (uint256 price, ) = getPrice(asset_, Variant.CURRENT);
        return price;
    }

    function getPrice(address asset_, uint48 maxAge_) external view override returns (uint256) {
        return _getPriceWithMaxAge(asset_, maxAge_);
    }

    function getPrice(
        address asset_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        // Mimic PRICE's behaviour of reverting if the asset is not approved
        if (!assetApproved[asset_]) revert PRICE_AssetNotApproved(asset_);

        uint256 price;
        uint48 priceTimestamp;
        if (variant_ == Variant.CURRENT) {
            price = prices[asset_];
            priceTimestamp = timestamp;
        } else if (variant_ == Variant.LAST) {
            // Return last stored price, or 0 if never stored.
            // Test helper `setLastPrice` may intentionally set a zero timestamp with non-zero price.
            if (lastStoredTimestamps[asset_] == 0 && lastStoredPrices[asset_] == 0) {
                price = 0;
                priceTimestamp = 0;
            } else {
                price = lastStoredPrices[asset_];
                priceTimestamp = lastStoredTimestamps[asset_];
            }
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            price = movingAverages[asset_];
            priceTimestamp = timestamp;
        } else {
            revert PRICE_ParamsVariantInvalid(variant_);
        }

        // Mimic PRICE's behaviour of reverting
        if (price == 0) {
            revert PRICE_PriceZero(asset_);
        }

        return (price, priceTimestamp);
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
        uint256 assetPrice = _getPriceWithMaxAge(asset_, maxAge_);
        uint256 basePrice = _getPriceWithMaxAge(base_, maxAge_);
        return (assetPrice * 10 ** _decimals) / basePrice;
    }

    function getPriceIn(
        address asset_,
        address base_,
        Variant variant_
    ) public view override returns (uint256, uint48) {
        // Mimic PRICE's behaviour of reverting if either asset is not approved
        if (!assetApproved[asset_]) revert PRICE_AssetNotApproved(asset_);
        if (!assetApproved[base_]) revert PRICE_AssetNotApproved(base_);

        uint256 assetPrice;
        uint256 basePrice;
        uint48 priceTimestamp;
        if (variant_ == Variant.CURRENT) {
            assetPrice = prices[asset_];
            basePrice = prices[base_];
            priceTimestamp = timestamp;
        } else if (variant_ == Variant.LAST) {
            // Return last stored prices, or 0 if never stored
            if (lastStoredTimestamps[asset_] == 0) {
                assetPrice = 0;
            } else {
                assetPrice = lastStoredPrices[asset_];
            }
            if (lastStoredTimestamps[base_] == 0) {
                basePrice = 0;
            } else {
                basePrice = lastStoredPrices[base_];
            }
            // Use the earlier timestamp if they differ, or 0 if neither has been stored
            uint48 assetTimestamp = lastStoredTimestamps[asset_];
            uint48 baseTimestamp = lastStoredTimestamps[base_];
            if (assetTimestamp == 0 && baseTimestamp == 0) {
                priceTimestamp = 0;
            } else if (assetTimestamp == 0) {
                priceTimestamp = baseTimestamp;
            } else if (baseTimestamp == 0) {
                priceTimestamp = assetTimestamp;
            } else {
                priceTimestamp = assetTimestamp < baseTimestamp ? assetTimestamp : baseTimestamp;
            }
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            assetPrice = movingAverages[asset_];
            basePrice = movingAverages[base_];
            priceTimestamp = timestamp;
        } else {
            revert PRICE_ParamsVariantInvalid(variant_);
        }

        if (assetPrice == 0) revert PRICE_PriceZero(asset_);
        if (basePrice == 0) revert PRICE_PriceZero(base_);

        // Return asset price / base price
        return ((assetPrice * 10 ** _decimals) / basePrice, priceTimestamp);
    }

    function setPriceDecimals(uint8 decimals_) public {
        _decimals = decimals_;
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
                lastObservationTime: lastStoredTimestamps[asset_] != 0
                    ? lastStoredTimestamps[asset_]
                    : uint48(block.timestamp),
                cumulativeObs: 0,
                obs: observations[asset_],
                strategy: bytes(""),
                feeds: bytes("")
            });
    }

    function isAssetApproved(address) external pure override returns (bool) {
        return true;
    }

    function cachePrice(address asset_) external override {
        // Get current price
        (uint256 price, ) = getPrice(asset_, Variant.CURRENT);

        // Store the price and timestamp
        lastStoredPrices[asset_] = price;
        lastStoredTimestamps[asset_] = uint48(block.timestamp);

        // Emit event to match PRICEv2 behavior
        emit PriceCached(asset_, price, uint48(block.timestamp));
    }

    function storeObservation(address asset_) external override {
        // Get current price
        (uint256 price, ) = getPrice(asset_, Variant.CURRENT);

        // Store the price and timestamp
        lastStoredPrices[asset_] = price;
        lastStoredTimestamps[asset_] = uint48(block.timestamp);

        // Emit both events to match PRICEv2 behavior
        emit PriceStored(asset_, price, uint48(block.timestamp));
        emit PriceCached(asset_, price, uint48(block.timestamp));
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

    function updateAsset(address asset_, UpdateAssetParams memory params_) external override {}

    function storeObservations() external virtual override {
        // Iterate over all assets
        for (uint256 i = 0; i < _assets.length; i++) {
            address asset = _assets[i];
            if (asset == address(0)) continue;

            getPrice(asset, Variant.CURRENT);
        }
    }

    function _getPriceWithMaxAge(address asset_, uint48 maxAge_) internal view returns (uint256) {
        // Mimic PRICE's behaviour of reverting if the asset is not approved
        if (!assetApproved[asset_]) revert PRICE_AssetNotApproved(asset_);

        uint48 lastTimestamp = lastStoredTimestamps[asset_];
        bool useCachedPrice = lastTimestamp != 0 &&
            uint256(lastTimestamp) + uint256(maxAge_) >= block.timestamp;

        uint256 price = useCachedPrice ? lastStoredPrices[asset_] : prices[asset_];
        if (price == 0) revert PRICE_PriceZero(asset_);

        return price;
    }
}
/// forge-lint: disable-end(mixed-case-function)
