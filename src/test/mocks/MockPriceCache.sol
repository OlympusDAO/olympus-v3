// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract MockPriceCache is IPriceCache, IEnabler {
    struct InternalCachedPrice {
        uint256 token0PriceUsd;
        uint256 token1PriceUsd;
        uint48 updatedAt;
        uint80 roundId;
    }

    error PriceCache_InvalidPair(address asset_, address quote_);
    error PriceCache_AssetNotApproved(address asset_);

    bool public isEnabled = true;

    uint256 public cachePriceCallCount;
    uint256 public cachePriceIfNecessaryCallCount;
    address public lastAsset;
    address public lastQuote;
    uint48 public lastMaxAge;

    mapping(address asset => uint256 usdPrice) internal _usdPrices;
    mapping(bytes32 pairKey => InternalCachedPrice cache) internal _cachedPriceByPair;

    function setUsdPrice(address asset_, uint256 usdPrice_) external {
        _usdPrices[asset_] = usdPrice_;
    }

    function cachePrice(address asset_, address quote_) public override {
        if (!isEnabled) revert NotEnabled();
        if (asset_ == address(0) || quote_ == address(0) || asset_ == quote_) {
            revert PriceCache_InvalidPair(asset_, quote_);
        }
        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);

        uint256 assetPriceUsd = _usdPrices[asset_];
        uint256 quotePriceUsd = _usdPrices[quote_];
        if (assetPriceUsd == 0) revert PriceCache_AssetNotApproved(asset_);
        if (quotePriceUsd == 0) revert PriceCache_AssetNotApproved(quote_);

        InternalCachedPrice storage cache = _cachedPriceByPair[key];
        if (assetIsToken0) {
            cache.token0PriceUsd = assetPriceUsd;
            cache.token1PriceUsd = quotePriceUsd;
        } else {
            cache.token0PriceUsd = quotePriceUsd;
            cache.token1PriceUsd = assetPriceUsd;
        }
        cache.updatedAt = uint48(block.timestamp);
        cache.roundId++;

        cachePriceCallCount++;
        lastAsset = asset_;
        lastQuote = quote_;
    }

    function cachePriceIfNecessary(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) external override {
        if (!isEnabled) revert NotEnabled();

        cachePriceIfNecessaryCallCount++;
        lastAsset = asset_;
        lastQuote = quote_;
        lastMaxAge = maxAge_;

        if (isStale(asset_, quote_, maxAge_)) {
            cachePrice(asset_, quote_);
        }
    }

    function getCachedPrice(
        address asset_,
        address quote_
    ) public view override returns (CachedPrice memory cachedPrice) {
        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);
        InternalCachedPrice memory cache = _cachedPriceByPair[key];

        if (assetIsToken0) {
            cachedPrice.assetPriceUsd = cache.token0PriceUsd;
            cachedPrice.quotePriceUsd = cache.token1PriceUsd;
        } else {
            cachedPrice.assetPriceUsd = cache.token1PriceUsd;
            cachedPrice.quotePriceUsd = cache.token0PriceUsd;
        }
        cachedPrice.updatedAt = cache.updatedAt;
        cachedPrice.roundId = cache.roundId;
    }

    function isStale(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) public view override returns (bool stale) {
        CachedPrice memory cachedPrice = getCachedPrice(asset_, quote_);
        return
            cachedPrice.updatedAt == 0 ||
            block.timestamp > uint256(cachedPrice.updatedAt) + uint256(maxAge_);
    }

    function enable(bytes calldata) external override {
        if (isEnabled) revert NotDisabled();
        isEnabled = true;
        emit Enabled();
    }

    function disable(bytes calldata) external override {
        if (!isEnabled) revert NotEnabled();
        isEnabled = false;
        emit Disabled();
    }

    function _pairKey(
        address asset_,
        address quote_
    ) internal pure returns (bytes32 key_, bool assetIsToken0_) {
        if (asset_ < quote_) {
            return (keccak256(abi.encodePacked(asset_, quote_)), true);
        }

        return (keccak256(abi.encodePacked(quote_, asset_)), false);
    }
}
