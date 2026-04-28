// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";

contract MockPriceCache is IPriceCache, IEnabler, IERC165 {
    address internal constant _UNIT_OF_ACCOUNT = address(0x348);
    string internal constant _UNIT_OF_ACCOUNT_SYMBOL = "USD";

    struct InternalCachedPrice {
        uint256 token0PriceUsd;
        uint256 token1PriceUsd;
        uint64 token0Epoch;
        uint64 token1Epoch;
        uint48 updatedAt;
        uint80 roundId;
    }

    bool public isEnabled = true;
    bool public policyActive = true;
    address public kernel;
    address public priceModule;
    uint8 public override decimals = 18;

    uint256 public cachePriceCallCount;
    uint256 public cachePriceIfNecessaryCallCount;
    address public lastAsset;
    address public lastQuote;
    uint48 public lastMaxAge;

    mapping(address asset => uint256 usdPrice) internal _usdPrices;
    mapping(address asset => bool approved) internal _approvedAssets;
    mapping(address asset => IPriceCache.NonContractAssetMetadata metadata)
        internal _nonContractAssetMetadata;
    mapping(address asset => uint64 epoch) internal _assetEpoch;
    mapping(bytes32 pairKey => InternalCachedPrice cache) internal _cachedPriceByPair;

    constructor(address kernel_) {
        kernel = kernel_;
        _nonContractAssetMetadata[_UNIT_OF_ACCOUNT] = IPriceCache.NonContractAssetMetadata({
            registered: true,
            decimals: 18,
            symbol: _UNIT_OF_ACCOUNT_SYMBOL
        });
    }

    function setUsdPrice(address asset_, uint256 usdPrice_) external {
        _usdPrices[asset_] = usdPrice_;
        _approvedAssets[asset_] = true;
    }

    function setPriceModule(address priceModule_) external {
        priceModule = priceModule_;
    }

    function setPriceDecimals(uint8 decimals_) external {
        decimals = decimals_;
    }

    function assetDecimals(address asset_) external view override returns (uint8 decimals_) {
        return _assetDecimals(asset_);
    }

    function assetSymbol(address asset_) external view override returns (string memory symbol_) {
        return _assetSymbol(asset_);
    }

    function _assetDecimals(address asset_) internal view returns (uint8 decimals_) {
        if (asset_.code.length != 0) return IERC20(asset_).decimals();

        IPriceCache.NonContractAssetMetadata memory metadata = _nonContractAssetMetadata[asset_];
        if (!metadata.registered) {
            if (_approvedAssets[asset_]) {
                revert IPriceCache.PriceCache_NonContractAssetDecimalsNotRegistered(asset_);
            }
            revert IPriceCache.PriceCache_NonContractAssetNotRegistered(asset_);
        }

        return metadata.decimals;
    }

    function _assetSymbol(address asset_) internal view returns (string memory symbol_) {
        if (asset_.code.length != 0) return IERC20(asset_).symbol();

        IPriceCache.NonContractAssetMetadata memory metadata = _nonContractAssetMetadata[asset_];
        if (!metadata.registered) {
            if (_approvedAssets[asset_]) {
                revert IPriceCache.PriceCache_NonContractAssetSymbolNotRegistered(asset_);
            }
            revert IPriceCache.PriceCache_NonContractAssetNotRegistered(asset_);
        }

        return metadata.symbol;
    }

    function setNonContractAssetMetadata(
        address asset_,
        uint8 decimals_,
        string calldata symbol_
    ) external {
        IPriceCache.NonContractAssetMetadata storage metadata = _nonContractAssetMetadata[asset_];
        if (
            !metadata.registered ||
            metadata.decimals != decimals_ ||
            keccak256(bytes(metadata.symbol)) != keccak256(bytes(symbol_))
        ) {
            metadata.registered = true;
            metadata.decimals = decimals_;
            metadata.symbol = symbol_;
            unchecked {
                _assetEpoch[asset_]++;
            }
        }
    }

    function removeNonContractAssetMetadata(address asset_) external {
        if (asset_ == _UNIT_OF_ACCOUNT) {
            revert IPriceCache.PriceCache_InvalidAsset(asset_);
        }
        if (_nonContractAssetMetadata[asset_].registered) {
            unchecked {
                _assetEpoch[asset_]++;
            }
        }
        delete _nonContractAssetMetadata[asset_];
    }

    function setPolicyActive(bool policyActive_) external {
        policyActive = policyActive_;
    }

    function setAssetApproval(address asset_, bool approved_) external {
        _approvedAssets[asset_] = approved_;
    }

    function clearCachedPrice(address asset_, address quote_) external {
        (bytes32 key, ) = _pairKey(asset_, quote_);
        delete _cachedPriceByPair[key];
    }

    function cachePrice(address asset_, address quote_) public override {
        if (!policyActive) revert IPriceCache.PriceCache_PolicyNotActive();
        if (!isEnabled) revert NotEnabled();
        _validatePair(asset_, quote_);
        _assetDecimals(asset_);
        _assetDecimals(quote_);
        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);

        uint256 assetPriceUsd = _getUsdPriceOrUnit(asset_);
        uint256 quotePriceUsd = _getUsdPriceOrUnit(quote_);
        uint64 assetEpoch = _assetEpoch[asset_];
        uint64 quoteEpoch = _assetEpoch[quote_];

        InternalCachedPrice storage cache = _cachedPriceByPair[key];
        if (assetIsToken0) {
            cache.token0PriceUsd = assetPriceUsd;
            cache.token1PriceUsd = quotePriceUsd;
            cache.token0Epoch = assetEpoch;
            cache.token1Epoch = quoteEpoch;
        } else {
            cache.token0PriceUsd = quotePriceUsd;
            cache.token1PriceUsd = assetPriceUsd;
            cache.token0Epoch = quoteEpoch;
            cache.token1Epoch = assetEpoch;
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
        if (!policyActive) revert IPriceCache.PriceCache_PolicyNotActive();
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
        if (!policyActive) revert IPriceCache.PriceCache_PolicyNotActive();

        _validatePair(asset_, quote_);
        _assetDecimals(asset_);
        _assetDecimals(quote_);

        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);
        InternalCachedPrice memory cache = _cachedPriceByPair[key];
        bool pairIsInvalidated;

        if (assetIsToken0) {
            pairIsInvalidated =
                cache.token0Epoch != _assetEpoch[asset_] ||
                cache.token1Epoch != _assetEpoch[quote_];
        } else {
            pairIsInvalidated =
                cache.token0Epoch != _assetEpoch[quote_] ||
                cache.token1Epoch != _assetEpoch[asset_];
        }

        if (pairIsInvalidated) {
            return cachedPrice;
        }

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

    function _validatePair(address asset_, address quote_) internal view {
        if (asset_ == address(0) || quote_ == address(0) || asset_ == quote_) {
            revert IPriceCache.PriceCache_InvalidPair(asset_, quote_);
        }

        if (!_isApprovedAssetOrUnit(asset_)) revert IPRICEv2.PRICE_AssetNotApproved(asset_);
        if (!_isApprovedAssetOrUnit(quote_)) revert IPRICEv2.PRICE_AssetNotApproved(quote_);
    }

    function _isApprovedAssetOrUnit(address asset_) internal view returns (bool) {
        return asset_ == _UNIT_OF_ACCOUNT || _approvedAssets[asset_];
    }

    function _getUsdPriceOrUnit(address asset_) internal view returns (uint256 usdPrice_) {
        if (asset_ == _UNIT_OF_ACCOUNT) return 10 ** uint256(decimals);
        return _usdPrices[asset_];
    }

    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return
            interfaceId_ == type(IPriceCache).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
    }
}
