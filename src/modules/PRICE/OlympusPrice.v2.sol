/// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";

// Bophades
import {Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {fromSubKeycode} from "src/Submodules.sol";

/// @title      OlympusPriceV2
/// @author     Oighty
/// @notice     Provides current and historical prices for assets
contract OlympusPricev2 is PRICEv2, IVersioned {
    // DONE
    // [X] Update functions for asset price feeds, strategies, etc.
    // [X] Toggle MA on and off for an asset
    // [X] Add "store" functions that call a view function, store the result, and return the value
    // [X] Update add asset functions to account for new data structures
    // [X] Update existing view functions to use new data structures
    // [X] custom errors
    // [X] implementation details in function comments
    // [X] define and emit events: addAsset, removeAsset, update price feeds, update price strategy, update moving average

    // ========== CONSTRUCTOR ========== //

    /// @notice                         Constructor to create OlympusPrice V2
    /// @dev                            The constructor reverts if:
    /// @dev                            - `observationFrequency_` is invalid (zero)
    ///
    /// @param kernel_                  Kernel address
    /// @param decimals_                Decimals that all prices will be returned with
    /// @param observationFrequency_    Frequency at which prices are stored for moving average
    constructor(Kernel kernel_, uint8 decimals_, uint32 observationFrequency_) Module(kernel_) {
        if (observationFrequency_ == 0)
            revert PRICE_ObservationFrequencyInvalid(observationFrequency_);

        _decimals = decimals_;
        _observationFrequency = observationFrequency_;
    }

    // ========== KERNEL FUNCTIONS ========== //

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    /// @inheritdoc IVersioned
    function VERSION()
        external
        pure
        virtual
        override(IVersioned, Module)
        returns (uint8 major, uint8 minor)
    {
        major = 2;
        minor = 0;
    }

    // ========== ERC165 FUNCTIONS ========== //

    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IVersioned).interfaceId || super.supportsInterface(interfaceId_);
    }

    ////////////////////////////////////////////////////////////////
    //                      DATA FUNCTIONS                        //
    ////////////////////////////////////////////////////////////////

    // ========== ASSET INFORMATION ========== //

    /// @inheritdoc IPRICEv2
    function getAssets() external view override returns (address[] memory) {
        return assets;
    }

    /// @inheritdoc IPRICEv2
    function getAssetData(address asset_) external view override returns (Asset memory) {
        return _assetData[asset_];
    }

    /// @inheritdoc IPRICEv2
    function isAssetApproved(address asset_) external view override returns (bool) {
        return _assetData[asset_].approved;
    }

    /// @notice         Returns true if `asset_` is the reserved unit-of-account asset
    function _isUnitOfAccount(address asset_) internal pure returns (bool) {
        return asset_ == _UNIT_OF_ACCOUNT;
    }

    /// @notice         Returns the unit price scaled to PRICE decimals
    function _unitPrice() internal view returns (uint256) {
        return 10 ** _decimals;
    }

    /// @notice         Reverts unless `asset_` is an approved asset
    function _validateApprovedAsset(address asset_) internal view {
        if (!_assetData[asset_].approved) revert PRICE_AssetNotApproved(asset_);
    }

    /// @notice         Reverts unless `asset_` is approved or the reserved unit of account
    function _validateApprovedAssetOrUnit(address asset_) internal view {
        if (_isUnitOfAccount(asset_)) return;
        _validateApprovedAsset(asset_);
    }

    /// @notice                 Returns the canonical storage key for an asset/quote pair
    ///
    /// @param asset_           The asset address
    /// @param quote_           The quote address
    /// @return key_            The storage key for the pair's cached price
    /// @return assetIsToken0_  A boolean indicating whether `asset_` is token0 in the canonical ordering
    function _pairKey(
        address asset_,
        address quote_
    ) internal pure returns (bytes32 key_, bool assetIsToken0_) {
        if (asset_ < quote_) {
            return (keccak256(abi.encodePacked(asset_, quote_)), true);
        }

        return (keccak256(abi.encodePacked(quote_, asset_)), false);
    }

    function _getCachedPrice(
        address asset_,
        address quote_
    ) internal view returns (uint256 assetPriceUsd_, uint256 quotePriceUsd_, uint48 updatedAt_) {
        // TODO consider shifting checks upstream
        if (asset_ == quote_) revert PRICE_ParamsPairInvalid(asset_, quote_);

        _validateApprovedAssetOrUnit(asset_);
        _validateApprovedAssetOrUnit(quote_);

        // Attempt to fetch a cached value for the asset pair, regardless of the orientation
        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);
        PairPriceCache memory cache = _pairCaches[key];
        if (cache.updatedAt == 0) return (0, 0, 0);

        // Determine the correct ordering of the return values
        assetPriceUsd_ = assetIsToken0 ? cache.token0PriceUsd : cache.token1PriceUsd;
        quotePriceUsd_ = assetIsToken0 ? cache.token1PriceUsd : cache.token0PriceUsd;
        updatedAt_ = cache.updatedAt;
    }

    /// @notice                 Returns the cached direct `asset_/quote_` price and metadata
    /// @dev                    Callers should handle identical operands before reaching this helper.
    /// @dev                    Uses `_getCachedPrice(asset_, quote_)` and derives the direct pair quote
    ///                         from the oriented USD legs.
    function _getLastPairQuote(
        address asset_,
        address quote_
    ) internal view returns (uint256 price_, uint48 updatedAt_) {
        (uint256 assetPriceUsd, uint256 quotePriceUsd, uint48 updatedAt) = _getCachedPrice(
            asset_,
            quote_
        );
        if (assetPriceUsd == 0 || quotePriceUsd == 0) return (0, 0);

        return (FullMath.mulDiv(assetPriceUsd, _unitPrice(), quotePriceUsd), updatedAt);
    }

    /// @notice                     Returns the current USD price for an asset, or the unit price for the unit of account
    ///
    /// @param  asset_              The asset to get the price for
    /// @return price_              The current price of the asset in USD (scaled to PRICE decimals)
    /// @return timestamp_          The current block timestamp
    /// @return successAllFeeds_    A boolean indicating whether all price feeds used to calculate the price were successful
    function _getCurrentPriceOrUnit(
        address asset_
    ) internal view returns (uint256 price_, uint48 timestamp_, bool successAllFeeds_) {
        if (_isUnitOfAccount(asset_)) {
            return (_unitPrice(), uint48(block.timestamp), true);
        }

        return _getCurrentPrice(asset_, true);
    }

    // ========== ASSET PRICES ========== //

    /// @inheritdoc IPRICEv2
    /// @dev        Optimistically uses the cached price if it has been updated this block, otherwise calculates price dynamically
    ///
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - No price could be determined
    function getPrice(address asset_) external view override returns (uint256) {
        return _getPriceInStale(asset_, _UNIT_OF_ACCOUNT, 0);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Checks cache first (no observation array check since storeObservation updates cache)
    /// @dev        Fallback order: cache → fresh calculation
    /// @dev        The reserved unit of account always returns `10 ** decimals()`.
    ///
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - The max age is >= the block timestamp
    function getPrice(address asset_, uint48 maxAge_) external view override returns (uint256) {
        // Check that max age is valid
        uint48 currentTime = uint48(block.timestamp);
        if (maxAge_ >= currentTime) revert PRICE_ParamsMaxAgeInvalid(maxAge_);

        return _getPriceInStale(asset_, _UNIT_OF_ACCOUNT, currentTime - maxAge_);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        The reserved unit of account returns:
    /// @dev        - `(10 ** decimals(), block.timestamp)` for `Variant.CURRENT`
    /// @dev        - `(10 ** decimals(), block.timestamp)` for `Variant.LAST`
    /// @dev        - reverts `PRICE_MovingAverageNotStored(asset_)` for `Variant.MOVINGAVERAGE`
    /// @dev
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - No price could be determined
    /// @dev        - An invalid variant is requested
    function getPrice(
        address asset_,
        Variant variant_
    ) public view override returns (uint256 _price, uint48 _timestamp) {
        return _getAssetPriceVariant(asset_, variant_);
    }

    /// @notice                 Returns the requested per-asset price variant and timestamp
    /// @dev                    `Variant.LAST` reads the cached `asset_/unitOfAccount()` pair snapshot.
    /// @dev                    `Variant.MOVINGAVERAGE` is always per-asset state and never pair-derived.
    /// @dev
    /// @dev                    Will revert if:
    /// @dev                    - `asset_` is not approved and is not the reserved unit of account
    /// @dev                    - the moving average is not stored for `asset_`
    /// @dev                    - `variant_` is invalid
    function _getAssetPriceVariant(
        address asset_,
        Variant variant_
    ) internal view returns (uint256 _price, uint48 _timestamp) {
        if (_isUnitOfAccount(asset_)) {
            if (variant_ == Variant.MOVINGAVERAGE) revert PRICE_MovingAverageNotStored(asset_);
            return (_unitPrice(), uint48(block.timestamp));
        }

        // Check if asset is approved
        _validateApprovedAsset(asset_);

        // Route to correct price function based on requested variant
        if (variant_ == Variant.CURRENT) {
            (uint256 price_, uint48 timestamp_, ) = _getCurrentPrice(asset_, true);
            return (price_, timestamp_);
        } else if (variant_ == Variant.LAST) {
            return _getLastPairQuote(asset_, _UNIT_OF_ACCOUNT);
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            // Inlined _getMovingAveragePrice logic
            Asset memory asset = _assetData[asset_];
            if (!asset.storeMovingAverage) revert PRICE_MovingAverageNotStored(asset_);
            return (asset.cumulativeObs / asset.numObservations, asset.lastObservationTime);
        } else {
            revert PRICE_ParamsVariantInvalid(variant_);
        }
    }

    /// @notice             Gets the raw feed prices for an asset
    ///
    /// @param asset_       The address of the asset
    /// @return uint256[]   Array of raw feed prices
    /// @return bool        Flag indicating if all feeds were successful
    function _getFeedPrices(address asset_) internal view returns (uint256[] memory, bool) {
        Asset storage asset = _assetData[asset_];
        Component[] memory feeds = abi.decode(asset.feeds, (Component[]));
        uint256 numFeeds = feeds.length;
        uint256[] memory prices = new uint256[](numFeeds);
        uint8 __decimals = _decimals;
        bool successAllFeeds = true;

        // Iterate through feeds to get prices to aggregate with strategy
        for (uint256 i; i < numFeeds; ) {
            (bool success_, bytes memory data_) = address(_getSubmoduleIfInstalled(feeds[i].target))
                .staticcall(
                    abi.encodeWithSelector(feeds[i].selector, asset_, __decimals, feeds[i].params)
                );

            // Store price if successful, otherwise leave as zero
            // Idea is that if you have several price calls and just
            // one fails, it'll DOS the contract with this revert.
            // We handle faulty feeds in the strategy contract.
            if (success_) {
                prices[i] = abi.decode(data_, (uint256));
            }

            // If the feed call reverted or the price was zero, we need to mark that a failure has happened
            if (success_ == false || prices[i] == 0) {
                successAllFeeds = false;
            }

            unchecked {
                ++i;
            }
        }

        return (prices, successAllFeeds);
    }

    /// @notice             Aggregates an array of prices using the configured strategy
    ///
    /// @param asset_       The address of the asset
    /// @param prices_      The array of prices to aggregate
    /// @return uint256     The aggregated price
    function _aggregate(address asset_, uint256[] memory prices_) internal view returns (uint256) {
        // If there is only one price, ensure it is not zero and return
        // Otherwise, send to strategy to aggregate
        if (prices_.length == 1) {
            if (prices_[0] == 0) revert PRICE_PriceZero(asset_);
            return prices_[0];
        }

        // Get price from strategy
        Component memory strategy = abi.decode(_assetData[asset_].strategy, (Component));
        (bool success, bytes memory data) = address(_getSubmoduleIfInstalled(strategy.target))
            .staticcall(abi.encodeWithSelector(strategy.selector, prices_, strategy.params));

        // Ensure call was successful and price is not zero
        if (!success) revert PRICE_StrategyFailed(asset_, data);
        uint256 price = abi.decode(data, (uint256));
        if (price == 0) revert PRICE_PriceZero(asset_);

        return price;
    }

    /// @notice             Appends the moving average to an array of prices
    /// @dev                Assumes that the asset stores and uses the moving average
    ///
    /// @param asset_       Asset to get the moving average of
    /// @param prices_      Array of prices to append to
    /// @return uint256[]   The array of prices including the moving average
    function _getInclusivePrices(
        address asset_,
        uint256[] memory prices_
    ) internal view returns (uint256[] memory) {
        Asset storage asset = _assetData[asset_];
        uint256 numFeeds = prices_.length;
        uint256[] memory inclusivePrices = new uint256[](numFeeds + 1);
        for (uint256 i; i < numFeeds; ) {
            inclusivePrices[i] = prices_[i];
            unchecked {
                ++i;
            }
        }
        inclusivePrices[numFeeds] = asset.cumulativeObs / asset.numObservations;
        return inclusivePrices;
    }

    /// @notice                         Gets the current price of the asset
    /// @dev                            This function follows this logic:
    /// @dev                            - Get the price from each feed
    /// @dev                            - If using the moving average, append the moving average to the results
    /// @dev                            - If there is only one price and it is not zero, return it
    /// @dev                            - Process the prices with the configured strategy
    ///
    /// @dev                            Will revert if:
    /// @dev                            - The resulting price is zero
    /// @dev                            - The configured strategy cannot aggregate the prices
    /// @dev                            - The moving average is used, but is stale
    ///
    /// @param asset_                   Asset to get the price of
    /// @param includeMovingAverage_    Flag to indicate if the moving average should be included in the price calculation
    /// @return uint256                 The aggregated price
    /// @return uint48                  The current block timestamp
    /// @return bool                    Flag indicating if all feeds were successful
    function _getCurrentPrice(
        address asset_,
        bool includeMovingAverage_
    ) internal view returns (uint256, uint48, bool) {
        Asset storage asset = _assetData[asset_];

        (uint256[] memory prices, bool successAllFeeds) = _getFeedPrices(asset_);

        if (asset.useMovingAverage && includeMovingAverage_) {
            if (asset.lastObservationTime + _observationFrequency <= block.timestamp)
                revert PRICE_MovingAverageStale(asset_, asset.lastObservationTime);

            prices = _getInclusivePrices(asset_, prices);
        }

        return (_aggregate(asset_, prices), uint48(block.timestamp), successAllFeeds);
    }

    /// @notice                 Returns a per-asset price using cached data when it is fresh enough
    /// @dev                    Falls back to `_getCurrentPrice(asset_, true)` when the cached value is too old or missing.
    ///
    /// @param asset_           Asset to get price for
    /// @param stalenessTime_   Staleness threshold (0=current block, other=min acceptable timestamp)
    /// @return price           The asset price
    function _getPriceStale(
        address asset_,
        uint48 stalenessTime_
    ) internal view returns (uint256 price) {
        // The unit of account is always treated as fresh and equal to 1.0 in PRICE decimals.
        if (_isUnitOfAccount(asset_)) return _unitPrice();

        uint48 pTime;
        (price, pTime) = getPrice(asset_, Variant.LAST);
        if (stalenessTime_ == 0 ? pTime != uint48(block.timestamp) : pTime < stalenessTime_) {
            (price, , ) = _getCurrentPrice(asset_, true);
        }
    }

    /// @notice                 Gets a direct asset/quote price with cache staleness fallback
    /// @dev                    If `stalenessTime` is 0, the cached pair must have been refreshed in the
    ///                         current block to be used; otherwise the value must be at least that timestamp.
    /// @dev                    Falls back to current pricing per leg when a cached leg is stale or missing.
    function _getPriceInStale(
        address asset_,
        address quote_,
        uint48 stalenessTime_
    ) internal view returns (uint256 price_) {
        if (asset_ == quote_) return _unitPrice();

        uint256 assetPrice = _getPriceStale(asset_, stalenessTime_);
        uint256 quotePrice = _getPriceStale(quote_, stalenessTime_);
        return FullMath.mulDiv(assetPrice, 10 ** _decimals, quotePrice);
    }

    /// @notice                 Gets a direct asset/quote price for the requested variant
    /// @dev                    `Variant.LAST` reads the direct cached pair snapshot.
    /// @dev                    Other variants derive the pair price from the corresponding per-asset variant.
    function _getPriceInVariant(
        address asset_,
        address quote_,
        Variant variant_
    ) internal view returns (uint256 _price, uint48 _timestamp) {
        if (asset_ == quote_) return (_unitPrice(), uint48(block.timestamp));

        if (variant_ == Variant.LAST) {
            return _getLastPairQuote(asset_, quote_);
        }

        (uint256 assetPrice, uint48 assetTime) = _getAssetPriceVariant(asset_, variant_);
        (uint256 quotePrice, uint48 quoteTime) = _getAssetPriceVariant(quote_, variant_);
        return (
            FullMath.mulDiv(assetPrice, 10 ** _decimals, quotePrice),
            assetTime < quoteTime ? assetTime : quoteTime
        );
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Optimistically uses the cached price if it has been updated this block, otherwise calculates price dynamically
    /// @dev        If `quote_` is the unit of account, this is equivalent to `getPrice(asset_)`.
    function getPriceIn(address asset_, address quote_) external view override returns (uint256) {
        return _getPriceInStale(asset_, quote_, 0);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - `quote_` is not approved
    /// @dev        - No price could be determined
    /// @dev        - The max age is >= the block timestamp
    /// @dev
    /// @dev        If `quote_` is the unit of account, this is equivalent to `getPrice(asset_, maxAge_)`.
    function getPriceIn(
        address asset_,
        address quote_,
        uint48 maxAge_
    ) external view override returns (uint256) {
        if (maxAge_ >= block.timestamp) revert PRICE_ParamsMaxAgeInvalid(maxAge_);

        return _getPriceInStale(asset_, quote_, uint48(block.timestamp) - maxAge_);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        For `Variant.LAST`, reads the direct cached `asset_/quote_` pair snapshot.
    /// @dev        For `Variant.CURRENT` and `Variant.MOVINGAVERAGE`, derives the pair price from the
    ///             corresponding per-asset price variant.
    function getPriceIn(
        address asset_,
        address quote_,
        Variant variant_
    ) external view override returns (uint256, uint48) {
        return _getPriceInVariant(asset_, quote_, variant_);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Will revert if:
    /// @dev        - The caller is not permissioned
    /// @dev        - The asset/quote pair is invalid
    /// @dev        - One of the operands is neither approved nor the reserved unit of account
    /// @dev        - The price was not able to be determined
    /// @dev        If either side is the unit of account, only that direct pair cache is refreshed.
    /// @dev        Otherwise this refreshes three cache entries atomically at the same timestamp:
    /// @dev        - `asset_/unitOfAccount()`
    /// @dev        - `quote_/unitOfAccount()`
    /// @dev        - `asset_/quote_`
    /// @dev        Reentrancy note: `_getCurrentPrice()` resolves feeds/strategy via `staticcall`,
    ///             so callbacks cannot perform state-changing reentry.
    function cachePrice(address asset_, address quote_) external override permissioned {
        if (asset_ == quote_) revert PRICE_ParamsPairInvalid(asset_, quote_);

        _validateApprovedAssetOrUnit(asset_);
        _validateApprovedAssetOrUnit(quote_);

        (uint256 assetPriceUsd, uint48 assetTimestamp, ) = _getCurrentPriceOrUnit(asset_);
        (uint256 quotePriceUsd, uint48 quoteTimestamp, ) = _getCurrentPriceOrUnit(quote_);

        uint48 timestamp = assetTimestamp < quoteTimestamp ? assetTimestamp : quoteTimestamp;
        if (_isUnitOfAccount(asset_) || _isUnitOfAccount(quote_)) {
            _cachePair(asset_, quote_, assetPriceUsd, quotePriceUsd, timestamp);
            return;
        }

        _cachePrice(asset_, assetPriceUsd, timestamp);
        _cachePrice(quote_, quotePriceUsd, timestamp);
        _cachePair(asset_, quote_, assetPriceUsd, quotePriceUsd, timestamp);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Get the current price using `_getCurrentPrice()`
    /// @dev        - Store the price in the asset's observation array at the index corresponding to the asset's value of `nextObsIndex`
    /// @dev        - Updates the asset's `lastObservationTime` to the current block timestamp
    /// @dev        - Increments the asset's `nextObsIndex` by 1, wrapping around to 0 if necessary
    /// @dev        - If the asset is configured to store the moving average, update the `cumulativeObs` value subtracting the previous value and adding the new one
    /// @dev        - Emit a `PriceStored` event and `PriceCached` event
    ///
    /// @dev        Will revert if:
    /// @dev        - The asset is not approved
    /// @dev        - The asset does not store moving average
    /// @dev        - The caller is not permissioned
    /// @dev        - The price was not able to be determined
    ///
    /// @dev        Reentrancy note: feed/strategy resolution is done via `staticcall`, so callbacks
    /// @dev        cannot perform state-changing reentry.
    ///
    /// @dev        This function does not enforce a minimum frequency between observations,
    /// @dev        leaving the onus on the caller to perform validation.
    ///
    /// @param asset_   The address of the asset
    function storeObservation(address asset_) public override permissioned {
        _storeObservation(asset_);
    }

    /// @notice Stores an observation for an asset
    /// @dev    Will revert if:
    /// @dev    - The asset is not approved
    /// @dev    - The moving average is not stored for the asset
    /// @dev    - Getting the prices fails
    /// @dev    - Aggregating the prices fails
    ///
    /// @param asset_   The address of the asset
    function _storeObservation(address asset_) internal {
        Asset storage asset = _assetData[asset_];

        // Check if asset is approved
        if (!asset.approved) revert PRICE_AssetNotApproved(asset_);
        // Check if asset stores moving average
        if (!asset.storeMovingAverage) revert PRICE_MovingAverageNotStored(asset_);

        // Get the current feed prices for the asset
        (uint256[] memory feedPrices, ) = _getFeedPrices(asset_);

        // Calculate the raw price for the observation (excluding MA)
        uint256 obsPrice = _aggregate(asset_, feedPrices);

        // Store the data in the obs index
        uint256 oldestPrice = asset.obs[asset.nextObsIndex];
        asset.obs[asset.nextObsIndex] = obsPrice;

        // Update the last observation time and increment the next index
        uint48 currentTime = uint48(block.timestamp);
        asset.lastObservationTime = currentTime;
        asset.nextObsIndex = (asset.nextObsIndex + 1) % asset.numObservations;

        // Update the cumulative observation
        asset.cumulativeObs = asset.cumulativeObs + obsPrice - oldestPrice;

        // Emit PriceStored event (with raw observation price)
        emit PriceStored(asset_, obsPrice, currentTime);

        // Calculate the inclusive price for the cache (including updated MA)
        // This ensures the cache is consistent with what getPrice(asset_, true) would return
        uint256 cachePrice_;
        if (asset.useMovingAverage) {
            cachePrice_ = _aggregate(asset_, _getInclusivePrices(asset_, feedPrices));
        } else {
            cachePrice_ = obsPrice;
        }

        // Update cache with the inclusive price
        _cachePrice(asset_, cachePrice_, currentTime);
    }

    /// @notice                 Internal helper to update an asset/unit-of-account cache and emit cache events
    ///
    /// @param asset_           Asset to update the cache for
    /// @param price_           Price to cache
    /// @param timestamp_       Timestamp for the cache entry
    function _cachePrice(address asset_, uint256 price_, uint48 timestamp_) internal {
        _cachePair(asset_, _UNIT_OF_ACCOUNT, price_, _unitPrice(), timestamp_);
    }

    /// @notice                 Internal helper to update one canonical pair cache entry
    /// @dev                    The emitted event preserves the requested operand ordering while the
    ///                         stored cache key remains canonicalized internally.
    function _cachePair(
        address asset_,
        address quote_,
        uint256 assetPriceUsd_,
        uint256 quotePriceUsd_,
        uint48 timestamp_
    ) internal returns (uint48 updatedAt) {
        (bytes32 key, bool assetIsToken0) = _pairKey(asset_, quote_);
        PairPriceCache storage cache = _pairCaches[key];

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

    /// @inheritdoc IPRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Iterate over all assets
    /// @dev        - Ignores assets that do not store the moving average
    /// @dev        - Store the price for each asset using `storeObservation()`
    ///
    /// @dev        Reentrancy note: delegates to `storeObservation()`, which only reaches external
    /// @dev        price providers via `staticcall`.
    ///
    /// @dev        This function does not enforce a minimum frequency between observations,
    /// @dev        leaving the onus on the caller to perform validation.
    function storeObservations() public override permissioned {
        uint256 len = assets.length;
        for (uint256 i; i < len; ) {
            if (_assetData[assets[i]].storeMovingAverage) _storeObservation(assets[i]);
            unchecked {
                ++i;
            }
        }
    }

    // ========== ASSET MANAGEMENT ========== //

    /// @notice         Validates asset configuration for feeds, strategy, and moving average
    /// @dev            Will revert if:
    /// @dev            - Moving average is used but not stored
    /// @dev            - Multiple feeds exist but no strategy is configured
    /// @dev            - Only one feed exists but a strategy is configured
    ///
    /// @param asset_              Asset address for error reporting
    /// @param strategy_           Strategy component configuration
    /// @param feedCount_          Number of price feeds configured
    /// @param useMovingAverage_   Whether the moving average is used in price calculation
    /// @param storeMovingAverage_ Whether the moving average is stored
    function _validateAssetConfiguration(
        address asset_,
        Component memory strategy_,
        uint256 feedCount_,
        bool useMovingAverage_,
        bool storeMovingAverage_
    ) internal pure {
        // If not storing the moving average, validate that it's not being used by the strategy
        if (useMovingAverage_ && !storeMovingAverage_)
            revert PRICE_ParamsStoreMovingAverageRequired(asset_);

        // Determine the number of price feeds (including the moving average)
        uint256 numFeeds = feedCount_ + (useMovingAverage_ ? 1 : 0);

        // Strategy is required if there is more than one price feed
        if (numFeeds > 1 && fromSubKeycode(strategy_.target) == bytes20(0))
            revert PRICE_ParamsStrategyInsufficient(
                asset_,
                abi.encode(strategy_),
                feedCount_,
                useMovingAverage_
            );

        // Strategy is not supported if there is only one price feed
        if (numFeeds == 1 && fromSubKeycode(strategy_.target) != bytes20(0))
            revert PRICE_ParamsStrategyNotSupported(asset_);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Performs basic checks on the parameters
    /// @dev        - Sets the price strategy using `_updateAssetPriceStrategy()`
    /// @dev        - Sets the price feeds using `_updateAssetPriceFeeds()`
    /// @dev        - Sets the moving average data using `_updateAssetMovingAverage()`
    /// @dev        - Validates the configuration using `_getCurrentPrice()`, which will revert if there is a mis-configuration
    /// @dev        - Adds the asset to the `assets` array and marks it as approved
    ///
    /// @dev        Will revert if:
    /// @dev        - The caller is not permissioned
    /// @dev        - `asset_` is not a contract
    /// @dev        - `asset_` is already approved
    /// @dev        - The moving average is being used, but not stored
    /// @dev        - An empty strategy was specified, but the number of feeds requires a strategy
    /// @dev        - The call to get the current price of any feed fails
    /// @dev        Reentrancy note: feed/strategy validation uses `staticcall`, so callbacks cannot
    ///             perform state-changing reentry.
    function addAsset(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        Component memory strategy_,
        Component[] memory feeds_
    ) external override permissioned {
        if (_isUnitOfAccount(asset_)) revert PRICE_AssetReserved(asset_);

        // Check that asset is a contract
        if (asset_.code.length == 0) revert PRICE_AssetNotContract(asset_);

        Asset storage asset = _assetData[asset_];

        // Ensure asset is not already added
        if (asset.approved) revert PRICE_AssetAlreadyApproved(asset_);

        // Validate asset configuration
        _validateAssetConfiguration(
            asset_,
            strategy_,
            feeds_.length,
            useMovingAverage_,
            storeMovingAverage_
        );

        // Update asset strategy data
        _updateAssetPriceStrategy(asset_, strategy_, useMovingAverage_);

        // Update asset price feed data
        _updateAssetPriceFeeds(asset_, feeds_);

        // Update asset moving average data
        _updateAssetMovingAverage(
            asset_,
            storeMovingAverage_,
            movingAverageDuration_,
            lastObservationTime_,
            observations_
        );

        // Validate configuration and optionally update cache
        (uint256 price, uint48 timestamp, bool successAllFeeds) = _getCurrentPrice(asset_, true);
        if (!successAllFeeds) revert PRICE_PriceFeedCallFailed(asset_);

        // If a single initial observation was provided for a non-MA asset, use that as the cached price.
        // Otherwise, cache the factual inclusive price.
        uint256 priceToCache = (observations_.length == 1 && !useMovingAverage_)
            ? observations_[0]
            : price;

        uint48 timestampToCache = (observations_.length == 1 && !useMovingAverage_)
            ? lastObservationTime_
            : timestamp;

        _cachePrice(asset_, priceToCache, timestampToCache);

        // Set asset as approved and add to array
        asset.approved = true;
        assets.push(asset_);

        // Emit event
        emit AssetAdded(asset_);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - The caller is not permissioned
    /// @dev        Reentrancy note: this function does not make external calls.
    function removeAsset(address asset_) external override permissioned {
        if (_isUnitOfAccount(asset_)) revert PRICE_AssetReserved(asset_);

        // Ensure asset is already added
        if (!_assetData[asset_].approved) revert PRICE_AssetNotApproved(asset_);

        // Remove asset from array
        uint256 len = assets.length;
        for (uint256 i; i < len; ) {
            if (assets[i] == asset_) {
                assets[i] = assets[len - 1];
                assets.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }

        // Remove asset from mapping
        delete _assetData[asset_];

        // Emit event
        emit AssetRemoved(asset_);
    }

    /// @notice         Updates the price feeds for the asset
    /// @dev            Implements the following logic:
    /// @dev            - Performs basic checks on the parameters
    /// @dev            - Sets the price feeds for the asset
    ///
    /// @dev            Will revert if:
    /// @dev            - The number of feeds is zero
    /// @dev            - Any feed has a submodule that is not installed
    ///
    /// @param asset_   Asset to update the price feeds for
    /// @param feeds_   Array of price feed components
    function _updateAssetPriceFeeds(address asset_, Component[] memory feeds_) internal {
        // Validate feed component submodules are installed and update feed array
        uint256 len = feeds_.length;
        if (len == 0) revert PRICE_ParamsPriceFeedInsufficient(asset_, len, 1);

        bytes32[] memory hashes = new bytes32[](len);

        for (uint256 i; i < len; ) {
            // Check that the submodule is installed
            if (!_submoduleIsInstalled(feeds_[i].target))
                revert PRICE_SubmoduleNotInstalled(asset_, abi.encode(feeds_[i].target));

            // Confirm that the feed is not a duplicate by checking the hash against hashes of previous feeds in the array
            /// forge-lint: disable-start(asm-keccak256)
            bytes32 hash = keccak256(
                abi.encode(feeds_[i].target, feeds_[i].selector, feeds_[i].params)
            );
            /// forge-lint: disable-end(asm-keccak256)

            for (uint256 j; j < i; ) {
                if (hash == hashes[j]) revert PRICE_DuplicatePriceFeed(asset_, i);
                unchecked {
                    ++j;
                }
            }

            hashes[i] = hash;

            unchecked {
                ++i;
            }
        }

        _assetData[asset_].feeds = abi.encode(feeds_);
    }

    /// @notice                     Updates the price strategy for the asset
    /// @dev                        Implements the following logic:
    /// @dev                        - Performs basic checks on the parameters
    /// @dev                        - Sets the price strategy for the asset
    /// @dev                        - Sets the `useMovingAverage` flag for the asset
    ///
    /// @dev                        Will revert if:
    /// @dev                        - The submodule used by the strategy is not installed
    ///
    /// @param asset_               Asset to update the price strategy for
    /// @param strategy_            Price strategy component
    /// @param useMovingAverage_    Flag to indicate if the moving average should be used in the strategy
    function _updateAssetPriceStrategy(
        address asset_,
        Component memory strategy_,
        bool useMovingAverage_
    ) internal {
        // Validate strategy component submodule is installed (if a strategy is being used)
        // A strategy is optional if there is only one price feed being used.
        // The number of feeds is checked in the external functions that call this one.
        if (
            fromSubKeycode(strategy_.target) != bytes20(0) &&
            !_submoduleIsInstalled(strategy_.target)
        ) revert PRICE_SubmoduleNotInstalled(asset_, abi.encode(strategy_.target));

        // Update the asset price strategy
        _assetData[asset_].strategy = abi.encode(strategy_);

        // Update whether the strategy uses a moving average (should be checked that the moving average is stored for the asset prior to sending to this function)
        _assetData[asset_].useMovingAverage = useMovingAverage_;
    }

    /// @notice                         Updates the moving average data for the asset
    /// @dev                            Implements the following logic:
    /// @dev                            - Removes existing moving average data
    /// @dev                            - Performs basic checks on the parameters
    /// @dev                            - Sets the moving average data for the asset
    /// @dev                            - If the moving average is not stored, deletes any existing observation data.
    /// @dev                            - IMPORTANT: This function does NOT update the price cache. Callers are responsible for updating the cache.
    ///
    /// @dev                            Will revert if:
    /// @dev                            - `lastObservationTime_` is in the future
    /// @dev                            - Any observation is zero
    /// @dev                            - The number of observations provided is insufficient
    ///
    /// @param asset_                   Asset to update the moving average data for
    /// @param storeMovingAverage_      Flag to indicate if the moving average should be stored
    /// @param movingAverageDuration_   Duration of the moving average
    /// @param lastObservationTime_     Timestamp of the last observation
    /// @param observations_            Array of observations to store
    function _updateAssetMovingAverage(
        address asset_,
        bool storeMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) internal {
        Asset storage asset = _assetData[asset_];

        // Remove existing cached or moving average data, if any
        if (asset.obs.length > 0) delete asset.obs;

        // Ensure last observation time is not in the future
        if (lastObservationTime_ > block.timestamp)
            revert PRICE_ParamsLastObservationTimeInvalid(
                asset_,
                lastObservationTime_,
                0,
                uint48(block.timestamp)
            );

        asset.storeMovingAverage = storeMovingAverage_;
        asset.cumulativeObs = 0;

        if (storeMovingAverage_) {
            // If storing a moving average, validate params
            if (
                movingAverageDuration_ == 0 ||
                uint48(movingAverageDuration_) % _observationFrequency != 0
            )
                revert PRICE_ParamsMovingAverageDurationInvalid(
                    asset_,
                    movingAverageDuration_,
                    _observationFrequency
                );

            uint16 numObservations = SafeCast.encodeUInt16(
                uint48(movingAverageDuration_) / _observationFrequency
            );
            if (observations_.length != numObservations || numObservations < 2)
                revert PRICE_ParamsInvalidObservationCount(
                    asset_,
                    observations_.length,
                    numObservations,
                    numObservations
                );

            asset.movingAverageDuration = movingAverageDuration_;
            asset.nextObsIndex = 0;
            asset.numObservations = numObservations;
            asset.lastObservationTime = lastObservationTime_;

            for (uint256 i; i < numObservations; ) {
                // Validate and store each observation
                if (observations_[i] == 0) revert PRICE_ParamsObservationZero(asset_, i);

                asset.cumulativeObs += observations_[i];
                asset.obs.push(observations_[i]);
                unchecked {
                    ++i;
                }
            }

            uint256 lastObsPrice = observations_[numObservations - 1];

            // Emit Price Stored event for new observation
            emit PriceStored(asset_, lastObsPrice, lastObservationTime_);
        } else {
            // If not storing moving average, validate that at most 1 observation is provided
            if (observations_.length > 1)
                revert PRICE_ParamsInvalidObservationCount(asset_, observations_.length, 0, 1);

            if (observations_.length == 1 && observations_[0] == 0)
                revert PRICE_ParamsObservationZero(asset_, 0);
        }
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Validates that at least one update flag is true
    /// @dev        - Validates that asset is approved
    /// @dev        - Calculates final state (before any updates)
    /// @dev        - Validates the final configuration atomically
    /// @dev        - Validates submodules are installed for updated components
    /// @dev        - Calls update functions for flagged updates
    /// @dev        - Validates final configuration with `_getCurrentPrice()`
    /// @dev        - Emits events based on which updates occurred
    ///
    /// @dev        Will revert if:
    /// @dev        - All update flags are false (no-op)
    /// @dev        - `asset_` is not approved
    /// @dev        - The final configuration is invalid
    /// @dev        - Any updated submodule is not installed
    /// @dev        Reentrancy note: any external feed/strategy resolution in validation uses
    ///             `staticcall`, so callbacks cannot perform state-changing reentry.
    function updateAsset(
        address asset_,
        UpdateAssetParams memory params_
    ) external override permissioned {
        if (_isUnitOfAccount(asset_)) revert PRICE_AssetReserved(asset_);

        // Validate at least one update flag is true
        if (!params_.updateFeeds && !params_.updateStrategy && !params_.updateMovingAverage)
            revert PRICE_NoUpdatesRequested(asset_);

        // Validate asset is approved
        if (!_assetData[asset_].approved) revert PRICE_AssetNotApproved(asset_);

        // Get current asset state
        Asset storage asset = _assetData[asset_];

        // Calculate final state (use new values if updating, otherwise keep existing)
        Component[] memory finalFeeds = params_.updateFeeds
            ? params_.feeds
            : abi.decode(asset.feeds, (Component[]));
        Component memory finalStrategy = params_.updateStrategy
            ? params_.strategy
            : abi.decode(asset.strategy, (Component));
        bool finalUseMA = params_.updateStrategy
            ? params_.useMovingAverage
            : asset.useMovingAverage;
        bool finalStoreMA = params_.updateMovingAverage
            ? params_.storeMovingAverage
            : asset.storeMovingAverage;

        // Validate the end state (before any updates)
        _validateAssetConfiguration(
            asset_,
            finalStrategy,
            finalFeeds.length,
            finalUseMA,
            finalStoreMA
        );

        // Call update functions (only after validation passes)
        if (params_.updateFeeds) {
            _updateAssetPriceFeeds(asset_, params_.feeds);
        }

        if (params_.updateStrategy) {
            _updateAssetPriceStrategy(asset_, params_.strategy, params_.useMovingAverage);
        }

        if (params_.updateMovingAverage) {
            _updateAssetMovingAverage(
                asset_,
                params_.storeMovingAverage,
                params_.movingAverageDuration,
                params_.lastObservationTime,
                params_.observations
            );
        }

        // Validate final configuration atomically and optionally update cache
        (uint256 price, uint48 timestamp, bool successAllFeeds) = _getCurrentPrice(asset_, true);
        if (!successAllFeeds) revert PRICE_PriceFeedCallFailed(asset_);

        // If a single initial observation was provided for a non-MA asset, use that as the cached price.
        // Otherwise, cache the factual inclusive price.
        uint256 priceToCache = (params_.updateMovingAverage &&
            params_.observations.length == 1 &&
            !params_.useMovingAverage)
            ? params_.observations[0]
            : price;

        uint48 timestampToCache = (params_.updateMovingAverage &&
            params_.observations.length == 1 &&
            !params_.useMovingAverage)
            ? params_.lastObservationTime
            : timestamp;

        _cachePrice(asset_, priceToCache, timestampToCache);

        // Emit events (based on which updates occurred)
        if (params_.updateFeeds) emit AssetPriceFeedsUpdated(asset_);
        if (params_.updateStrategy) emit AssetPriceStrategyUpdated(asset_);
        if (params_.updateMovingAverage) emit AssetMovingAverageUpdated(asset_);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
