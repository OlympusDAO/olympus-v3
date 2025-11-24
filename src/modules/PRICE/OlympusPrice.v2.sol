/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/modules/PRICE/PRICE.v2.sol";

/// @title      OlympusPriceV2
/// @author     Oighty
/// @notice     Provides current and historical prices for assets
contract OlympusPricev2 is PRICEv2 {
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

        decimals = decimals_;
        observationFrequency = observationFrequency_;
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

    // ========== MODIFIERS ========== //

    ////////////////////////////////////////////////////////////////
    //                      DATA FUNCTIONS                        //
    ////////////////////////////////////////////////////////////////

    // ========== ASSET INFORMATION ========== //

    /// @inheritdoc PRICEv2
    function getAssets() external view override returns (address[] memory) {
        return assets;
    }

    /// @inheritdoc PRICEv2
    function getAssetData(address asset_) external view override returns (Asset memory) {
        return _assetData[asset_];
    }

    /// @inheritdoc PRICEv2
    function isAssetApproved(address asset_) external view override returns (bool) {
        return _assetData[asset_].approved;
    }

    // ========== ASSET PRICES ========== //

    /// @inheritdoc PRICEv2
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

    /// @inheritdoc PRICEv2
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - No price could be determined
    /// @dev        - The max age is >= the block timestamp
    function getPrice(address asset_, uint48 maxAge_) external view override returns (uint256) {
        // Check that max age is valid
        if (maxAge_ >= uint48(block.timestamp)) revert PRICEv2.PRICE_ParamsMaxAgeInvalid(maxAge_);

        // Try to use the last price, must be updated more recently than maxAge
        // getPrice checks if asset is approved
        (uint256 price, uint48 timestamp) = getPrice(asset_, Variant.LAST);
        if (timestamp >= uint48(block.timestamp) - maxAge_) return price;

        // If last price is stale, use the current price
        (price, , ) = _getCurrentPrice(asset_, true);
        return price;
    }

    /// @inheritdoc PRICEv2
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
            return _getLastPrice(asset_);
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            return _getMovingAveragePrice(asset_);
        }
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
    /// @return                         The price of the asset
    /// @return                         The current block timestamp
    /// @return                         Flag to indicate if all feeds were successful
    function _getCurrentPrice(
        address asset_,
        bool includeMovingAverage_
    ) internal view returns (uint256, uint48, bool) {
        Asset storage asset = _assetData[asset_];

        // Iterate through feeds to get prices to aggregate with strategy
        Component[] memory feeds = abi.decode(asset.feeds, (Component[]));
        uint256 numFeeds = feeds.length;
        uint256[] memory prices = asset.useMovingAverage && includeMovingAverage_
            ? new uint256[](numFeeds + 1)
            : new uint256[](numFeeds);
        uint8 _decimals = decimals; // cache in memory to save gas
        bool successAllFeeds = true;
        for (uint256 i; i < numFeeds; ) {
            (bool success_, bytes memory data_) = address(_getSubmoduleIfInstalled(feeds[i].target))
                .staticcall(
                    abi.encodeWithSelector(feeds[i].selector, asset_, _decimals, feeds[i].params)
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

        // If moving average is used and it is meant to be included, add to end of prices array
        if (asset.useMovingAverage && includeMovingAverage_) {
            // Check if the moving average is stale
            // If the observation frequency has passed (including in the current block), it is stale and should be updated
            if (asset.lastObservationTime + observationFrequency <= block.timestamp)
                revert PRICE_MovingAverageStale(asset_, asset.lastObservationTime);

            prices[numFeeds] = asset.cumulativeObs / asset.numObservations;
        }

        // If there is only one price, ensure it is not zero and return
        // Otherwise, send to strategy to aggregate
        if (prices.length == 1) {
            if (prices[0] == 0) revert PRICE_PriceZero(asset_);
            return (prices[0], uint48(block.timestamp), successAllFeeds);
        } else {
            // Get price from strategy
            Component memory strategy = abi.decode(asset.strategy, (Component));
            (bool success, bytes memory data) = address(_getSubmoduleIfInstalled(strategy.target))
                .staticcall(abi.encodeWithSelector(strategy.selector, prices, strategy.params));

            // Ensure call was successful
            if (!success) revert PRICE_StrategyFailed(asset_, data);

            // Decode asset price
            uint256 price = abi.decode(data, (uint256));

            // Ensure value is not zero
            if (price == 0) revert PRICE_PriceZero(asset_);

            return (price, uint48(block.timestamp), successAllFeeds);
        }
    }

    /// @notice         Gets the last cached price of the asset
    /// @dev            This function follows this logic:
    /// @dev            - Get the last observation stored for the asset and return it
    ///
    /// @dev            If no price has been ever cached, this function will automatically
    /// @dev            return (0, 0).
    ///
    /// @param asset_   Asset to get the price of
    /// @return         The price of the asset and asset's last observation time
    function _getLastPrice(address asset_) internal view returns (uint256, uint48) {
        // Load asset data
        Asset memory asset = _assetData[asset_];

        // Get last observation stored for asset
        uint256 lastPrice = asset.obs[
            asset.nextObsIndex == 0 ? asset.numObservations - 1 : asset.nextObsIndex - 1
        ];

        // Last price doesn't have to be checked for zero because it is checked before being stored

        // Return last price and time
        return (lastPrice, asset.lastObservationTime);
    }

    /// @notice         Gets the moving average price of the asset
    /// @dev            This function follows this logic:
    /// @dev            - Calculate the moving average using the `cumulativeObs` / `numObservations`
    ///
    /// @dev            Will revert if:
    /// @dev            - The moving average is not stored for the asset
    ///
    /// @param asset_   Asset to get the price of
    /// @return         The price of the asset and asset's last observation time
    function _getMovingAveragePrice(address asset_) internal view returns (uint256, uint48) {
        // Load asset data
        Asset memory asset = _assetData[asset_];

        // Check if moving average is stored for asset
        if (!asset.storeMovingAverage) revert PRICE_MovingAverageNotStored(asset_);

        // Calculate moving average
        uint256 movingAverage = asset.cumulativeObs / asset.numObservations;

        // Moving average doesn't have to be checked for zero because each value is checked before being stored

        // Return moving average and time
        return (movingAverage, asset.lastObservationTime);
    }

    /// @inheritdoc PRICEv2
    /// @dev        Optimistically uses the cached price if it has been updated this block, otherwise calculates price dynamically
    function getPriceIn(address asset_, address base_) external view override returns (uint256) {
        // Get the last price of each asset (getPrice checks if asset is approved)
        (uint256 assetPrice, uint48 assetTime) = getPrice(asset_, Variant.LAST);
        (uint256 basePrice, uint48 baseTime) = getPrice(base_, Variant.LAST);

        // Try to use the last prices, timestamp must be current
        // If stale, get current price
        if (assetTime != uint48(block.timestamp)) {
            (assetPrice, , ) = _getCurrentPrice(asset_, true);
        }
        if (baseTime != uint48(block.timestamp)) {
            (basePrice, , ) = _getCurrentPrice(base_, true);
        }

        // Calculate the price of the asset in the base and return
        return (assetPrice * 10 ** decimals) / basePrice;
    }

    /// @inheritdoc PRICEv2
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
        // Check that max age is valid
        if (maxAge_ == 0) revert PRICEv2.PRICE_ParamsMaxAgeInvalid(maxAge_);
        if (maxAge_ >= uint48(block.timestamp)) revert PRICEv2.PRICE_ParamsMaxAgeInvalid(maxAge_);

        // Get the last price of each asset (getPrice checks if asset is approved)
        (uint256 assetPrice, uint48 assetTime) = getPrice(asset_, Variant.LAST);
        (uint256 basePrice, uint48 baseTime) = getPrice(base_, Variant.LAST);

        // Try to use the last prices, timestamp must be no older than maxAge_
        // If stale, get current price
        if (assetTime < uint48(block.timestamp) - maxAge_) {
            (assetPrice, , ) = _getCurrentPrice(asset_, true);
        }
        if (baseTime < uint48(block.timestamp) - maxAge_) {
            (basePrice, , ) = _getCurrentPrice(base_, true);
        }

        // Calculate the price of the asset in the base and return
        return (assetPrice * 10 ** decimals) / basePrice;
    }

    /// @inheritdoc PRICEv2
    function getPriceIn(
        address asset_,
        address base_,
        Variant variant_
    ) external view override returns (uint256, uint48) {
        // Get the price of the asset (checks if approved)
        (uint256 assetPrice, uint48 assetTime) = getPrice(asset_, variant_);

        // Get the price of the base (checks if approved)
        (uint256 basePrice, uint48 baseTime) = getPrice(base_, variant_);

        // The updatedAt timestamp is the minimum of the two price updatedAt timestamps
        uint48 updatedAt = assetTime < baseTime ? assetTime : baseTime;

        // Calculate the price of the asset in the base
        uint256 price = (assetPrice * 10 ** decimals) / basePrice;

        return (price, updatedAt);
    }

    /// @inheritdoc PRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Get the current price using `_getCurrentPrice()`
    /// @dev        - Store the price in the asset's observation array at the index corresponding to the asset's value of `nextObsIndex`
    /// @dev        - Updates the asset's `lastObservationTime` to the current block timestamp
    /// @dev        - Increments the asset's `nextObsIndex` by 1, wrapping around to 0 if necessary
    /// @dev        - If the asset is configured to store the moving average, update the `cumulativeObs` value subtracting the previous value and adding the new one
    /// @dev        - Emit a `PriceStored` event
    ///
    /// @dev        Will revert if:
    /// @dev        - The asset is not approved
    /// @dev        - The caller is not permissioned
    /// @dev        - The price was not able to be determined
    function storePrice(address asset_) public override permissioned {
        Asset storage asset = _assetData[asset_];

        // Check if asset is approved
        if (!asset.approved) revert PRICE_AssetNotApproved(asset_);

        // Get the current price for the asset
        (uint256 price, uint48 currentTime, ) = _getCurrentPrice(asset_, false);

        // Store the data in the obs index
        uint256 oldestPrice = asset.obs[asset.nextObsIndex];
        asset.obs[asset.nextObsIndex] = price;

        // Update the last observation time and increment the next index
        asset.lastObservationTime = currentTime;
        asset.nextObsIndex = (asset.nextObsIndex + 1) % asset.numObservations;

        // Update the cumulative observation, if storing the moving average
        if (asset.storeMovingAverage)
            asset.cumulativeObs = asset.cumulativeObs + price - oldestPrice;

        // Emit event
        emit PriceStored(asset_, price, currentTime);
    }

    /// @inheritdoc PRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Iterate over all assets
    /// @dev        - Ignores assets that do not store the moving average
    /// @dev        - Store the price for each asset using `storePrice()`
    function storeObservations() public override permissioned {
        // Iterate through assets and store the price for each
        uint256 len = assets.length;

        for (uint256 i; i < len; ) {
            address currentAsset = assets[i];
            Asset memory asset = _assetData[currentAsset];

            // Only process if the moving average is stored
            if (asset.approved && asset.storeMovingAverage) {
                storePrice(currentAsset);
            }

            unchecked {
                ++i;
            }
        }
    }

    // ========== ASSET MANAGEMENT ========== //

    /// @inheritdoc PRICEv2
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
    ) external override permissioned {
        // Check that asset is a contract
        if (asset_.code.length == 0) revert PRICE_AssetNotContract(asset_);

        Asset storage asset = _assetData[asset_];

        // Ensure asset is not already added
        if (asset.approved) revert PRICE_AssetAlreadyApproved(asset_);

        // If not storing the moving average, validate that it's not being used by the strategy
        if (useMovingAverage_ && !storeMovingAverage_)
            revert PRICE_ParamsStoreMovingAverageRequired(asset_);

        // Strategy cannot be zero if number of feeds + useMovingAverage is greater than 1
        if (
            (feeds_.length + (useMovingAverage_ ? 1 : 0)) > 1 &&
            fromSubKeycode(strategy_.target) == bytes20(0)
        )
            revert PRICE_ParamsStrategyInsufficient(
                asset_,
                abi.encode(strategy_),
                feeds_.length,
                useMovingAverage_
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

        // Validate configuration
        (, , bool successAllFeeds) = _getCurrentPrice(asset_, true);
        if (!successAllFeeds) revert PRICE_PriceFeedCallFailed(asset_);

        // Set asset as approved and add to array
        asset.approved = true;
        assets.push(asset_);

        // Emit event
        emit AssetAdded(asset_);
    }

    /// @inheritdoc PRICEv2
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - The caller is not permissioned
    function removeAsset(address asset_) external override permissioned {
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

    /// @inheritdoc PRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Performs basic checks on the parameters
    /// @dev        - Sets the price feeds using `_updateAssetPriceFeeds()`
    /// @dev        - Validates the configuration using `_getCurrentPrice()`, which will revert if there is a mis-configuration
    ///
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - The caller is not permissioned
    /// @dev        - `_updateAssetPriceFeeds()` reverts
    /// @dev        - `_getCurrentPrice()` reverts
    /// @dev        - The asset strategy is not compatible with the number of feeds
    function updateAssetPriceFeeds(
        address asset_,
        Component[] memory feeds_
    ) external override permissioned {
        // Ensure asset is already added
        Asset storage assetData = _assetData[asset_];
        if (!assetData.approved) revert PRICE_AssetNotApproved(asset_);

        // Check if the strategy and price feeds are still compatible
        {
            Component memory strategy = abi.decode(assetData.strategy, (Component));

            if (
                (feeds_.length + (assetData.useMovingAverage ? 1 : 0)) > 1 &&
                fromSubKeycode(strategy.target) == bytes20(0)
            )
                revert PRICE_ParamsStrategyInsufficient(
                    asset_,
                    assetData.strategy,
                    feeds_.length,
                    assetData.useMovingAverage
                );
        }

        _updateAssetPriceFeeds(asset_, feeds_);

        // Validate the configuration
        _getCurrentPrice(asset_, true);

        // Emit event
        emit AssetPriceFeedsUpdated(asset_);
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
            bytes32 _hash = keccak256(
                abi.encode(feeds_[i].target, feeds_[i].selector, feeds_[i].params)
            );

            for (uint256 j; j < i; ) {
                if (_hash == hashes[j]) revert PRICE_DuplicatePriceFeed(asset_, i);
                unchecked {
                    ++j;
                }
            }

            hashes[i] = _hash;

            unchecked {
                ++i;
            }
        }

        _assetData[asset_].feeds = abi.encode(feeds_);
    }

    /// @inheritdoc PRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Performs basic checks on the parameters
    /// @dev        - Sets the price strategy using `_updateAssetPriceStrategy()`
    /// @dev        - Validates the configuration using `_getCurrentPrice()`, which will revert if there is a mis-configuration
    ///
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - The caller is not permissioned
    /// @dev        - The moving average is used, but is not stored
    /// @dev        - An empty strategy was specified, but the number of feeds requires a strategy
    function updateAssetPriceStrategy(
        address asset_,
        Component memory strategy_,
        bool useMovingAverage_
    ) external override permissioned {
        // Ensure asset is already added
        if (!_assetData[asset_].approved) revert PRICE_AssetNotApproved(asset_);

        // Validate that the moving average is stored for the asset to use in strategy
        if (useMovingAverage_ && !_assetData[asset_].storeMovingAverage)
            revert PRICE_ParamsStoreMovingAverageRequired(asset_);

        // Strategy cannot be zero if number of feeds + useMovingAverage is greater than 1
        Component[] memory feeds = abi.decode(_assetData[asset_].feeds, (Component[]));
        if (
            (feeds.length + (useMovingAverage_ ? 1 : 0)) > 1 &&
            fromSubKeycode(strategy_.target) == bytes20(0)
        )
            revert PRICE_ParamsStrategyInsufficient(
                asset_,
                abi.encode(strategy_),
                feeds.length,
                useMovingAverage_
            );

        _updateAssetPriceStrategy(asset_, strategy_, useMovingAverage_);

        // Validate
        _getCurrentPrice(asset_, true);

        // Emit event
        emit AssetPriceStrategyUpdated(asset_);
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

    /// @inheritdoc                     PRICEv2
    /// @dev                            Implements the following logic:
    /// @dev                            - Performs basic checks on the parameters
    /// @dev                            - Sets the moving average data using `_updateAssetMovingAverage()`
    ///
    /// @dev                            Will revert if:
    /// @dev                            - `asset_` is not approved
    /// @dev                            - The caller is not permissioned
    /// @dev                            - The moving average is used, but is not stored
    ///
    /// @param asset_                   Asset to update the moving average data for
    /// @param storeMovingAverage_      Flag to indicate if the moving average should be stored
    /// @param movingAverageDuration_   Duration of the moving average
    /// @param lastObservationTime_     Timestamp of the last observation
    /// @param observations_            Array of observations to store
    function updateAssetMovingAverage(
        address asset_,
        bool storeMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external override permissioned {
        // Ensure asset is already added
        if (!_assetData[asset_].approved) revert PRICE_AssetNotApproved(asset_);

        // If not storing the moving average, validate that it's not being used by the strategy.
        // If it is, then you are moving from storing a moving average to not storing a moving average.
        // First, change the strategy to not use the moving average, then update the moving average data.
        if (_assetData[asset_].useMovingAverage && !storeMovingAverage_)
            revert PRICE_ParamsStoreMovingAverageRequired(asset_);

        _updateAssetMovingAverage(
            asset_,
            storeMovingAverage_,
            movingAverageDuration_,
            lastObservationTime_,
            observations_
        );

        // Emit event
        emit AssetMovingAverageUpdated(asset_);
    }

    /// @notice                         Updates the moving average data for the asset
    /// @dev                            Implements the following logic:
    /// @dev                            - Removes existing moving average data
    /// @dev                            - Performs basic checks on the parameters
    /// @dev                            - Sets the moving average data for the asset
    /// @dev                            - If the moving average is not stored, gets the current price and stores it so that every asset has at least one cached value
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

        if (storeMovingAverage_) {
            // If storing a moving average, validate params
            if (movingAverageDuration_ == 0 || movingAverageDuration_ % observationFrequency != 0)
                revert PRICE_ParamsMovingAverageDurationInvalid(
                    asset_,
                    movingAverageDuration_,
                    observationFrequency
                );

            uint16 numObservations = uint16(movingAverageDuration_ / observationFrequency);
            if (observations_.length != numObservations || numObservations < 2)
                revert PRICE_ParamsInvalidObservationCount(
                    asset_,
                    observations_.length,
                    numObservations,
                    numObservations
                );

            asset.storeMovingAverage = true;

            asset.movingAverageDuration = movingAverageDuration_;
            asset.nextObsIndex = 0;
            asset.numObservations = numObservations;
            asset.lastObservationTime = lastObservationTime_;
            asset.cumulativeObs = 0; // reset to zero before adding new observations
            for (uint256 i; i < numObservations; ) {
                if (observations_[i] == 0) revert PRICE_ParamsObservationZero(asset_, i);

                asset.cumulativeObs += observations_[i];
                asset.obs.push(observations_[i]);
                unchecked {
                    ++i;
                }
            }

            // Emit Price Stored event for new cached value
            emit PriceStored(asset_, observations_[numObservations - 1], lastObservationTime_);
        } else {
            // If not storing the moving average, validate that the array has at most one value (for caching)
            if (observations_.length > 1)
                revert PRICE_ParamsInvalidObservationCount(asset_, observations_.length, 0, 1);

            asset.storeMovingAverage = false;
            asset.movingAverageDuration = 0;
            asset.nextObsIndex = 0;
            asset.numObservations = 1;
            if (observations_.length == 0) {
                // If no observation provided, get the current price and store it
                // We can do this here because we know the moving average isn't being stored
                // and therefore, it is not being used in the strategy to calculate the price
                (uint256 currentPrice, uint48 timestamp, ) = _getCurrentPrice(asset_, false);
                asset.obs.push(currentPrice);
                asset.lastObservationTime = timestamp;

                // Emit Price Stored event for new cached value
                emit PriceStored(asset_, currentPrice, timestamp);
            } else {
                // If an observation is provided, validate it and store it
                if (observations_[0] == 0) revert PRICE_ParamsObservationZero(asset_, 0);

                asset.obs.push(observations_[0]);
                asset.lastObservationTime = lastObservationTime_;

                // Emit Price Stored event for new cached value
                emit PriceStored(asset_, observations_[0], lastObservationTime_);
            }

            // We don't track cumulativeObs when not storing the moving average, even though there is one data point in the array for caching
            asset.cumulativeObs = 0;
        }
    }
}
