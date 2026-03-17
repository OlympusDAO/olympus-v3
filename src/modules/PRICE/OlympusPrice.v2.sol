/// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

// Libraries
import {SafeCast} from "src/libraries/SafeCast.sol";
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";

// Bophades
import {Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {fromSubKeycode} from "src/Submodules.sol";

/// @title      OlympusPriceV2
/// @author     Oighty
/// @notice     Provides current and historical prices for assets
contract OlympusPricev2 is PRICEv2, IVersioned, ReentrancyGuard {
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

    // ========== ASSET PRICES ========== //

    /// @inheritdoc IPRICEv2
    /// @dev        Optimistically uses the cached price if it has been updated this block, otherwise calculates price dynamically
    ///
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - No price could be determined
    function getPrice(address asset_) external view override returns (uint256) {
        // Try to use the last price, must be updated on the current timestamp
        // getPrice checks if asset is approved
        (uint256 price, uint48 timestamp) = getPrice(asset_, Variant.LAST);
        if (timestamp == uint48(block.timestamp)) return price;

        // If last price is stale, use the current price
        (price, , ) = _getCurrentPrice(asset_, true);
        return price;
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Checks cache first (no observation array check since storeObservation updates cache)
    /// @dev        Fallback order: cache → fresh calculation
    ///
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - The max age is >= the block timestamp
    function getPrice(address asset_, uint48 maxAge_) external view override returns (uint256) {
        // Check that max age is valid
        uint48 currentTime = uint48(block.timestamp);
        if (maxAge_ >= currentTime) revert PRICE_ParamsMaxAgeInvalid(maxAge_);

        // Try to use the last price, must be updated more recently than maxAge
        // getPrice checks if asset is approved
        (uint256 lastPrice, uint48 lastTimestamp) = getPrice(asset_, Variant.LAST);
        if (lastTimestamp > 0 && lastTimestamp >= currentTime - maxAge_) {
            return lastPrice;
        }

        // Calculate fresh price
        (uint256 price, , ) = _getCurrentPrice(asset_, true);
        return price;
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - No price could be determined
    /// @dev        - An invalid variant is requested
    function getPrice(
        address asset_,
        Variant variant_
    ) public view override returns (uint256 _price, uint48 _timestamp) {
        // Check if asset is approved
        if (!_assetData[asset_].approved) revert PRICE_AssetNotApproved(asset_);

        // Route to correct price function based on requested variant
        if (variant_ == Variant.CURRENT) {
            (uint256 price_, uint48 timestamp_, ) = _getCurrentPrice(asset_, true);
            return (price_, timestamp_);
        } else if (variant_ == Variant.LAST) {
            // Return cached price (populated by addAsset, cachePrice, or storeObservation)
            PriceCache memory cache = _cachedPrices[asset_];
            return (cache.price, cache.cachedAt);
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

    /// @notice                 Gets price with staleness check, returns single value
    /// @dev                    Internal helper for getPriceIn functions
    /// @param asset_           Asset to get price for
    /// @param stalenessTime    Staleness threshold (0=exact match, other=min acceptable timestamp)
    /// @return price           The asset price
    function _getPriceStale(
        address asset_,
        uint48 stalenessTime
    ) internal view returns (uint256 price) {
        uint48 pTime;
        (price, pTime) = getPrice(asset_, Variant.LAST);
        if (stalenessTime == 0 ? pTime != uint48(block.timestamp) : pTime < stalenessTime) {
            (price, , ) = _getCurrentPrice(asset_, true);
        }
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Optimistically uses the cached price if it has been updated this block, otherwise calculates price dynamically
    function getPriceIn(address asset_, address base_) external view override returns (uint256) {
        uint256 assetPrice = _getPriceStale(asset_, 0);
        uint256 basePrice = _getPriceStale(base_, 0);
        // assetPrice and basePrice use 10 ** _decimals scale (USD); result keeps 10 ** _decimals scale.
        return (assetPrice * 10 ** _decimals) / basePrice;
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - `base_` is not approved
    /// @dev        - No price could be determined
    /// @dev        - The max age is 0 (as that would return a current value)
    /// @dev        - The max age is >= the block timestamp
    function getPriceIn(
        address asset_,
        address base_,
        uint48 maxAge_
    ) external view override returns (uint256) {
        if (maxAge_ == 0 || maxAge_ >= block.timestamp) revert PRICE_ParamsMaxAgeInvalid(maxAge_);
        uint48 cutoff = uint48(block.timestamp) - maxAge_;
        uint256 assetPrice = _getPriceStale(asset_, cutoff);
        uint256 basePrice = _getPriceStale(base_, cutoff);
        // assetPrice and basePrice use 10 ** _decimals scale (USD); result keeps 10 ** _decimals scale.
        return (assetPrice * 10 ** _decimals) / basePrice;
    }

    /// @inheritdoc IPRICEv2
    function getPriceIn(
        address asset_,
        address base_,
        Variant variant_
    ) external view override returns (uint256, uint48) {
        (uint256 assetPrice, uint48 assetTime) = getPrice(asset_, variant_);
        (uint256 basePrice, uint48 baseTime) = getPrice(base_, variant_);
        // assetPrice and basePrice use 10 ** _decimals scale (USD); result keeps 10 ** _decimals scale.
        return (
            (assetPrice * 10 ** _decimals) / basePrice,
            assetTime < baseTime ? assetTime : baseTime
        );
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Will revert if:
    /// @dev        - The caller is not permissioned
    /// @dev        - The asset is not approved
    /// @dev        - The price was not able to be determined
    function cachePrice(address asset_) external override permissioned nonReentrant {
        if (!_assetData[asset_].approved) revert PRICE_AssetNotApproved(asset_);

        (uint256 price, uint48 timestamp, ) = _getCurrentPrice(asset_, true);
        if (price == 0) revert PRICE_PriceZero(asset_);

        _cachedPrices[asset_] = PriceCache({price: price, cachedAt: timestamp});

        emit PriceCached(asset_, price, timestamp);
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
    function storeObservation(address asset_) public override permissioned nonReentrant {
        _storeObservation(asset_);
    }

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

    /// @notice                 Internal helper to update the price cache and emit PriceCached event
    ///
    /// @param asset_           Asset to update the cache for
    /// @param price_           Price to cache
    /// @param timestamp_       Timestamp for the cache entry
    function _cachePrice(address asset_, uint256 price_, uint48 timestamp_) internal {
        _cachedPrices[asset_] = PriceCache({price: price_, cachedAt: timestamp_});
        emit PriceCached(asset_, price_, timestamp_);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Iterate over all assets
    /// @dev        - Ignores assets that do not store the moving average
    /// @dev        - Store the price for each asset using `storeObservation()`
    function storeObservations() public override permissioned nonReentrant {
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
    /// @dev            Reverts if:
    /// @dev            - Moving average is used but not stored
    /// @dev            - Multiple feeds exist but no strategy is configured
    /// @dev            - Only one feed exists but a strategy is configured
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
    function addAsset(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        Component memory strategy_,
        Component[] memory feeds_
    ) external override permissioned nonReentrant {
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
    function removeAsset(address asset_) external override permissioned nonReentrant {
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
    function updateAsset(
        address asset_,
        UpdateAssetParams memory params_
    ) external override permissioned nonReentrant {
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
