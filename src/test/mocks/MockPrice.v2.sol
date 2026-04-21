// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function)
pragma solidity ^0.8.15;

import {Kernel, Module, Keycode, toKeycode} from "src/Kernel.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";

contract MockPrice is PRICEv2 {
    mapping(address => bool) internal assetApproved;
    mapping(address => uint256) internal prices;
    mapping(address => uint256) internal movingAverages;
    mapping(address => uint48) internal movingAverageLastUpdated;
    mapping(address => uint256[]) internal observations;
    mapping(bytes32 => PairPriceCache) internal pairCaches;
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
        movingAverageLastUpdated[asset] = uint48(block.timestamp);
    }

    function _isUnitOfAccount(address asset_) internal pure returns (bool) {
        return asset_ == _UNIT_OF_ACCOUNT;
    }

    function _unitPrice() internal view returns (uint256) {
        return 10 ** _decimals;
    }

    function _pairKey(
        address asset_,
        address base_
    ) internal pure returns (bytes32 key_, bool assetIsToken0_) {
        if (asset_ < base_) {
            return (keccak256(abi.encodePacked(asset_, base_)), true);
        }

        return (keccak256(abi.encodePacked(base_, asset_)), false);
    }

    function _cachePair(
        address asset_,
        address quote_,
        uint256 assetPriceUsd_,
        uint256 quotePriceUsd_,
        uint48 timestamp_
    ) internal returns (uint48 updatedAt) {
        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);
        PairPriceCache storage cache = pairCaches[key];

        if (assetIsToken0) {
            cache.token0PriceUsd = assetPriceUsd_;
            cache.token1PriceUsd = quotePriceUsd_;
        } else {
            cache.token0PriceUsd = quotePriceUsd_;
            cache.token1PriceUsd = assetPriceUsd_;
        }

        cache.updatedAt = timestamp_;

        emit PricePairCached(asset_, quote_, assetPriceUsd_, quotePriceUsd_, timestamp_);

        return cache.updatedAt;
    }

    function _getLastPairQuote(
        address asset_,
        address quote_
    ) internal view returns (uint256 price_, uint48 priceTimestamp_) {
        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);
        PairPriceCache memory cache = pairCaches[key];
        if (cache.updatedAt == 0) return (0, 0);

        uint256 assetPriceUsd = assetIsToken0 ? cache.token0PriceUsd : cache.token1PriceUsd;
        uint256 quotePriceUsd = assetIsToken0 ? cache.token1PriceUsd : cache.token0PriceUsd;
        if (assetPriceUsd == 0 || quotePriceUsd == 0) return (0, 0);

        return ((assetPriceUsd * (10 ** _decimals)) / quotePriceUsd, cache.updatedAt);
    }

    function _getCurrentPriceOrUnit(address asset_) internal view returns (uint256, uint48) {
        if (_isUnitOfAccount(asset_)) return (_unitPrice(), uint48(block.timestamp));
        return (prices[asset_], uint48(block.timestamp));
    }

    /// @notice Test helper to directly seed a cached pair snapshot.
    function setCachedPrice(
        address asset_,
        address quote_,
        uint256 assetPriceUsd_,
        uint256 quotePriceUsd_,
        uint48 timestamp_
    ) public {
        if (!_isUnitOfAccount(asset_)) assetApproved[asset_] = true;
        if (!_isUnitOfAccount(quote_)) assetApproved[quote_] = true;

        _cachePair(asset_, quote_, assetPriceUsd_, quotePriceUsd_, timestamp_);
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
        if (_isUnitOfAccount(asset_)) {
            if (variant_ == Variant.MOVINGAVERAGE) revert PRICE_AssetNotApproved(asset_);
            return (_unitPrice(), variant_ == Variant.CURRENT ? timestamp : 0);
        }

        // Mimic PRICE's behaviour of reverting if the asset is not approved
        if (!assetApproved[asset_]) revert PRICE_AssetNotApproved(asset_);

        uint256 price;
        uint48 priceTimestamp;
        if (variant_ == Variant.CURRENT) {
            price = prices[asset_];
            priceTimestamp = timestamp;
        } else if (variant_ == Variant.LAST) {
            (price, priceTimestamp) = _getLastPairQuote(asset_, _UNIT_OF_ACCOUNT);
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            price = movingAverages[asset_];
            priceTimestamp = movingAverageLastUpdated[asset_];
        } else {
            revert PRICE_ParamsVariantInvalid(variant_);
        }

        if (variant_ == Variant.LAST && price == 0) {
            return (0, 0);
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
        if (!_isUnitOfAccount(asset_) && !assetApproved[asset_])
            revert PRICE_AssetNotApproved(asset_);
        if (!_isUnitOfAccount(base_) && !assetApproved[base_]) revert PRICE_AssetNotApproved(base_);

        if (asset_ == base_) return (_unitPrice(), 0);

        uint256 assetPrice;
        uint256 basePrice;
        uint48 priceTimestamp;
        if (variant_ == Variant.CURRENT) {
            (assetPrice, priceTimestamp) = _getCurrentPriceOrUnit(asset_);
            (basePrice, ) = _getCurrentPriceOrUnit(base_);
        } else if (variant_ == Variant.LAST) {
            (uint256 price_, uint48 timestamp_) = _getLastPairQuote(asset_, base_);
            if (timestamp_ == 0) return (0, 0);
            return (price_, timestamp_);
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            assetPrice = movingAverages[asset_];
            basePrice = movingAverages[base_];
            priceTimestamp = movingAverageLastUpdated[asset_];
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

    function getAssets() external view override returns (address[] memory) {
        return _assets;
    }

    function getAssetData(address asset_) external view override returns (Asset memory) {
        return
            Asset({
                approved: true,
                storeMovingAverage: true,
                useMovingAverage: false,
                movingAverageDuration: 30 days,
                nextObsIndex: 0,
                numObservations: 90,
                lastObservationTime: movingAverageLastUpdated[asset_] != 0
                    ? movingAverageLastUpdated[asset_]
                    : uint48(block.timestamp),
                cumulativeObs: 0,
                obs: observations[asset_],
                strategy: bytes(""),
                feeds: bytes("")
            });
    }

    function isAssetApproved(address asset_) external view override returns (bool) {
        return assetApproved[asset_];
    }

    function cachePrice(address asset_, address base_) external override {
        if (!_isUnitOfAccount(asset_)) assetApproved[asset_] = true;
        if (!_isUnitOfAccount(base_)) assetApproved[base_] = true;

        (uint256 assetPriceUsd, uint48 assetTimestamp) = _getCurrentPriceOrUnit(asset_);
        (uint256 basePriceUsd, uint48 baseTimestamp) = _getCurrentPriceOrUnit(base_);
        uint48 cachedAt = assetTimestamp < baseTimestamp ? assetTimestamp : baseTimestamp;

        _cachePair(asset_, base_, assetPriceUsd, basePriceUsd, cachedAt);
    }

    function storeObservation(address asset_) external override {
        // Get current price
        (uint256 price, ) = getPrice(asset_, Variant.CURRENT);

        // Store the price and timestamp
        movingAverages[asset_] = price;
        movingAverageLastUpdated[asset_] = uint48(block.timestamp);
        _cachePair(asset_, _UNIT_OF_ACCOUNT, price, _unitPrice(), uint48(block.timestamp));

        // Emit both events to match PRICEv2 behavior
        emit PriceStored(asset_, price, uint48(block.timestamp));
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

    function removeAsset(address asset_) external override {
        assetApproved[asset_] = false;
    }

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
        if (_isUnitOfAccount(asset_)) return _unitPrice();

        // Mimic PRICE's behaviour of reverting if the asset is not approved
        if (!assetApproved[asset_]) revert PRICE_AssetNotApproved(asset_);

        // Get from the cache
        (uint256 cachedPrice, uint48 cachedTimestamp) = _getLastPairQuote(asset_, _UNIT_OF_ACCOUNT);

        bool useCachedPrice = cachedTimestamp != 0 &&
            uint256(cachedTimestamp) + uint256(maxAge_) >= block.timestamp;

        uint256 price = useCachedPrice ? cachedPrice : prices[asset_];
        if (price == 0) revert PRICE_PriceZero(asset_);

        return price;
    }
}
/// forge-lint: disable-end(mixed-case-function)
