/// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

// Interfaces
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";

// Bophades
import {Kernel, Keycode, Module, toKeycode} from "src/Kernel.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {fromSubKeycode, SubKeycode, Submodule} from "src/Submodules.sol";

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
    constructor(Kernel kernel_, uint8 decimals_, uint32 observationFrequency_) PRICEv2(kernel_) {
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

    /// @inheritdoc PRICEv2
    /// @dev        Does not revert.
    function supportsInterface(bytes4 interfaceId_) public pure virtual override returns (bool) {
        return
            interfaceId_ == type(IVersioned).interfaceId ||
            interfaceId_ == type(IPRICEv2).interfaceId ||
            interfaceId_ == type(IERC165).interfaceId;
    }

    ////////////////////////////////////////////////////////////////
    //                      DATA FUNCTIONS                        //
    ////////////////////////////////////////////////////////////////

    // ========== ASSET INFORMATION ========== //

    /// @inheritdoc IPRICEv2
    /// @dev        Does not revert.
    function getAssets() external view override returns (address[] memory) {
        return assets;
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Does not revert.
    function getAssetData(address asset_) external view override returns (Asset memory) {
        return _assetData[asset_];
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Does not revert.
    function isAssetApproved(address asset_) external view override returns (bool) {
        return _assetData[asset_].approved;
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Will revert if:
    /// @dev        - `asset_` is the zero address
    /// @dev        - `asset_` is a contract
    /// @dev        - `asset_` is already registered
    function registerNonContractAsset(address asset_) external override permissioned {
        if (asset_ == address(0) || asset_.code.length != 0 || isNonContractAsset[asset_])
            revert PRICE_InvalidAsset(asset_);

        isNonContractAsset[asset_] = true;
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Will revert if:
    /// @dev        - `asset_` is the reserved unit of account
    /// @dev        - `asset_` is not registered
    /// @dev        - `asset_` still has an active PRICE configuration
    function unregisterNonContractAsset(address asset_) external override permissioned {
        if (_isUnitOfAccount(asset_)) revert PRICE_AssetReserved(asset_);
        if (!isNonContractAsset[asset_] || _assetData[asset_].approved) {
            revert PRICE_InvalidAsset(asset_);
        }

        delete isNonContractAsset[asset_];
    }

    /// @notice         Returns true if `asset_` is the reserved unit-of-account asset
    /// @dev            Does not revert.
    function _isUnitOfAccount(address asset_) internal pure returns (bool) {
        return asset_ == _UNIT_OF_ACCOUNT;
    }

    /// @notice         Returns the unit price scaled to PRICE decimals
    /// @dev            Does not revert.
    function _unitPrice() internal view virtual returns (uint256) {
        return 10 ** _decimals;
    }

    /// @notice         Reverts unless `asset_` is an approved asset
    /// @dev            Will revert if:
    /// @dev            - `asset_` is not approved
    function _validateApprovedAsset(address asset_) internal view {
        if (!_assetData[asset_].approved) revert PRICE_AssetNotApproved(asset_);
    }

    /// @notice                 Returns the most recent stored observation for an asset
    /// @dev                    Will revert if:
    /// @dev                    - `asset_` does not store the moving average (and thus does not have stored observations)
    ///
    /// @param  asset_          The asset address
    /// @return price_          The most recent observation price
    /// @return timestamp_      The timestamp of the most recent stored observation
    function _getLastObservationPrice(
        address asset_
    ) internal view returns (uint256 price_, uint48 timestamp_) {
        Asset storage asset = _assetData[asset_];
        if (!asset.storeMovingAverage) revert PRICE_MovingAverageNotStored(asset_);

        uint16 nextIdx = asset.nextObsIndex;
        uint16 lastIdx;
        unchecked {
            lastIdx = nextIdx == 0 ? asset.numObservations - 1 : nextIdx - 1;
        }
        return (asset.obs[lastIdx], asset.lastObservationTime);
    }

    // ========== ASSET PRICES ========== //

    /// @inheritdoc IPRICEv2
    /// @dev        Returns the CURRENT variant from feeds/strategy (plus MA where configured).
    /// @dev        The reserved unit-of-account returns `10 ** decimals()`.
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved
    /// @dev        - No price could be determined
    function getPrice(address asset_) external view override returns (uint256) {
        if (_isUnitOfAccount(asset_)) return _unitPrice();

        _validateApprovedAsset(asset_);
        (uint256 price_, , ) = _getCurrentPrice(asset_, true);
        return price_;
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
    /// @dev        - `variant_ == Variant.CURRENT` and a configured moving average is stale
    /// @dev        - An invalid variant is requested
    function getPrice(
        address asset_,
        Variant variant_
    ) public view override returns (uint256 _price, uint48 _timestamp) {
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
            return _getLastObservationPrice(asset_);
        } else if (variant_ == Variant.MOVINGAVERAGE) {
            // Use storage here to avoid copying the full Asset struct (including the dynamic obs array) to memory.
            Asset storage asset = _assetData[asset_];
            if (!asset.storeMovingAverage) revert PRICE_MovingAverageNotStored(asset_);
            return (asset.cumulativeObs / asset.numObservations, asset.lastObservationTime);
        } else {
            revert PRICE_ParamsVariantInvalid(variant_);
        }
    }

    /// @notice             Gets the raw feed prices for an asset
    ///
    /// @param  asset_      The address of the asset
    /// @return uint256[]   Array of raw feed prices
    /// @return bool        Flag indicating if all feeds were successful
    function _getFeedPrices(address asset_) internal view returns (uint256[] memory, bool) {
        Asset storage asset = _assetData[asset_];
        Component[] memory feeds = abi.decode(asset.feeds, (Component[]));
        uint256 numFeeds = feeds.length;
        uint256[] memory prices = new uint256[](numFeeds);
        bool successAllFeeds = true;

        // Iterate through feeds to get prices to aggregate with strategy
        for (uint256 i; i < numFeeds; ) {
            (bool success_, bytes memory data_) = address(_getSubmoduleIfInstalled(feeds[i].target))
                .staticcall(
                    abi.encodeWithSelector(feeds[i].selector, asset_, _decimals, feeds[i].params)
                );

            // Store price if successful, otherwise leave as zero
            // Idea is that if you have several price calls and just
            // one fails, it'll DOS the contract with this revert.
            // We handle faulty feeds in the strategy contract.
            uint256 price;
            if (success_) {
                price = abi.decode(data_, (uint256));
                prices[i] = price;
            }

            // If the feed call reverted or the price was zero, we need to mark that a failure has happened
            if (price == 0) {
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
    /// @param prices_      Array of prices to aggregate
    /// @return uint256     The aggregated price
    function _aggregate(address asset_, uint256[] memory prices_) internal view returns (uint256) {
        Asset storage asset = _assetData[asset_];

        // Single-feed assets without MA do not need a strategy. Early exit.
        if (prices_.length == 1 && !asset.useMovingAverage) {
            if (prices_[0] == 0) revert PRICE_PriceZero(asset_);
            return prices_[0];
        }

        // Calculate the aggregated result using the strategy
        Component memory strategy = abi.decode(asset.strategy, (Component));
        (bool success, bytes memory data) = address(_getSubmoduleIfInstalled(strategy.target))
            .staticcall(abi.encodeWithSelector(strategy.selector, prices_, strategy.params));

        // Ensure call was successful and price is not zero
        if (!success) revert PRICE_StrategyFailed(asset_, data);

        uint256 price = abi.decode(data, (uint256));
        if (price == 0) revert PRICE_PriceZero(asset_);

        return price;
    }

    /// @notice             Appends a moving average value to an array of prices
    ///
    /// @param prices_      Array of prices to append to
    /// @param movingAverage_ Moving average value to append
    /// @return uint256[]   The array of prices including the moving average
    function _getInclusivePrices(
        uint256[] memory prices_,
        uint256 movingAverage_
    ) internal pure returns (uint256[] memory) {
        uint256 numFeeds = prices_.length;
        uint256[] memory inclusivePrices = new uint256[](numFeeds + 1);
        for (uint256 i; i < numFeeds; ) {
            inclusivePrices[i] = prices_[i];
            unchecked {
                ++i;
            }
        }
        inclusivePrices[numFeeds] = movingAverage_;
        return inclusivePrices;
    }

    /// @notice             Validates both runtime input shapes for a moving-average strategy
    /// @dev                The stored observation path must aggregate raw feed values only. The
    ///                     CURRENT path must aggregate raw feed values plus a moving average. This
    ///                     uses the raw observation value as a synthetic moving average to avoid
    ///                     rejecting updates solely because the stored moving average is stale.
    ///
    ///                     Assumes that the asset has useMovingAverage set to true.
    ///
    /// @param asset_       Asset to validate
    /// @return bool        Flag indicating if all feeds were successful
    function _validateMovingAverageStrategy(address asset_) internal view returns (bool) {
        (uint256[] memory prices, bool successAllFeeds) = _getFeedPrices(asset_);
        if (!successAllFeeds) return false;

        // First aggregate the raw prices into an observation
        // This mimics what is performed by storeObservation()
        // It will also validate the strategy
        uint256 obsPrice = _aggregate(asset_, prices);

        // Then attempt to aggregate the raw prices and the observation as a synthetic MA value.
        // Runtime CURRENT reads append the stored MA, but validation uses this synthetic value so a
        // stale stored MA does not prevent governance from recovering the asset configuration.
        _aggregate(asset_, _getInclusivePrices(prices, obsPrice));

        return successAllFeeds;
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
            _revertIfMovingAverageStale(asset_, asset.lastObservationTime);

            prices = _getInclusivePrices(prices, asset.cumulativeObs / asset.numObservations);
        }

        return (_aggregate(asset_, prices), uint48(block.timestamp), successAllFeeds);
    }

    /// @notice                     Reverts if the moving average observation is stale
    ///
    /// @param asset_               The asset address used in the revert payload
    /// @param lastObservationTime_ Last stored moving-average observation timestamp
    function _revertIfMovingAverageStale(
        address asset_,
        uint48 lastObservationTime_
    ) internal view {
        if (lastObservationTime_ + _observationFrequency <= block.timestamp)
            revert PRICE_MovingAverageStale(asset_, lastObservationTime_);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Returns the pair price from CURRENT per-asset values.
    /// @dev        If either side is the unit of account, that side resolves to `10 ** decimals()`.
    /// @dev        Will revert if:
    /// @dev        - `asset_` is not approved (and not the unit of account)
    /// @dev        - `quote_` is not approved (and not the unit of account)
    /// @dev        - No price could be determined for either non-unit asset
    function getPriceIn(address asset_, address quote_) external view override returns (uint256) {
        (uint256 assetPrice, ) = getPrice(asset_, Variant.CURRENT);
        (uint256 quotePrice, ) = getPrice(quote_, Variant.CURRENT);
        return FullMath.mulDiv(assetPrice, _unitPrice(), quotePrice);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Derives the pair quote from per-asset variants.
    /// @dev        Reverts if:
    /// @dev        - `variant_` is invalid
    /// @dev        - `asset_` is not approved (and not the unit of account)
    /// @dev        - `quote_` is not approved (and not the unit of account)
    /// @dev        - The requested variant is unavailable for either side
    /// @dev          (for example `Variant.LAST`/`Variant.MOVINGAVERAGE` without stored observations)
    /// @dev        - A price cannot be determined for either side
    function getPriceIn(
        address asset_,
        address quote_,
        Variant variant_
    ) external view override returns (uint256, uint48) {
        (uint256 assetPrice, uint48 assetTime) = getPrice(asset_, variant_);
        (uint256 quotePrice, uint48 quoteTime) = getPrice(quote_, variant_);
        return (
            FullMath.mulDiv(assetPrice, _unitPrice(), quotePrice),
            assetTime < quoteTime ? assetTime : quoteTime
        );
    }

    /// @inheritdoc IPRICEv2
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
    /// @dev        - The asset does not store moving average
    /// @dev        - The caller is not permissioned
    /// @dev        - The price was not able to be determined
    ///
    /// @dev        Reentrancy note: feed/strategy resolution is done via `staticcall`, so callbacks
    /// @dev        cannot perform state-changing reentry.
    ///
    /// @dev        This function enforces an implementation-defined earliest allowed timestamp for each
    /// @dev        asset observation write. The current implementation uses `lastObservationTime + 1`,
    /// @dev        which prevents same-block double writes.
    /// @dev        It does not enforce a larger minimum frequency between observations.
    /// @dev        Calling policies are responsible for cadence/epoch scheduling.
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
    /// @dev    - The observation timestamp is before the implementation-defined earliest allowed time
    /// @dev    - Cadence beyond same-block writes is not enforced in this module
    ///
    /// @param asset_   The address of the asset
    function _storeObservation(address asset_) internal {
        Asset storage asset = _assetData[asset_];

        // Check if asset is approved
        if (!asset.approved) revert PRICE_AssetNotApproved(asset_);
        // Check if asset stores moving average
        if (!asset.storeMovingAverage) revert PRICE_MovingAverageNotStored(asset_);
        uint48 observationTime = uint48(block.timestamp);
        uint48 earliestAllowedTime = asset.lastObservationTime;
        // Earliest allowed is implementation-defined; currently last observation + 1 second.
        if (earliestAllowedTime < type(uint48).max) earliestAllowedTime += 1;
        if (observationTime < earliestAllowedTime)
            revert PRICE_ObservationTooEarly(asset_, observationTime, earliestAllowedTime);

        // Get the current observation value (excludes MA contribution by design).
        (uint256 obsPrice, uint48 currentTime, ) = _getCurrentPrice(asset_, false);

        // Store the data in the obs index
        uint16 nextObsIndex = asset.nextObsIndex;
        uint256 oldestPrice = asset.obs[nextObsIndex];
        asset.obs[nextObsIndex] = obsPrice;

        // Update the last observation time and increment the next index
        asset.lastObservationTime = currentTime;
        unchecked {
            ++nextObsIndex;
        }
        if (nextObsIndex == asset.numObservations) nextObsIndex = 0;
        asset.nextObsIndex = nextObsIndex;

        // Update the cumulative observation
        asset.cumulativeObs = asset.cumulativeObs + obsPrice - oldestPrice;

        // Emit PriceStored event (with raw observation price)
        emit PriceStored(asset_, obsPrice, currentTime);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Iterate over all assets
    /// @dev        - Ignores assets that do not store the moving average
    /// @dev        - Store the price for each asset using `storeObservation()`
    /// @dev
    /// @dev        Reverts if:
    /// @dev        - The caller is not permissioned
    /// @dev        - Observation storage fails for any configured moving-average asset
    ///
    /// @dev        Reentrancy note: delegates to `storeObservation()`, which only reaches external
    /// @dev        price providers via `staticcall`.
    ///
    /// @dev        This function enforces an implementation-defined earliest allowed timestamp for each
    /// @dev        asset observation write. The current implementation uses `lastObservationTime + 1`,
    /// @dev        which prevents same-block double writes.
    /// @dev        It does not enforce a larger minimum frequency between observations.
    /// @dev        Calling policies are responsible for cadence/epoch scheduling.
    function storeObservations() public override permissioned {
        uint256 len = assets.length;
        for (uint256 i; i < len; ) {
            address asset = assets[i];
            if (_assetData[asset].storeMovingAverage) _storeObservation(asset);
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

    /// @notice         Validates the price feed components for an asset configuration
    /// @dev            Checks that at least one feed is supplied, each feed target is installed,
    ///                 and no exact feed component is duplicated.
    /// @dev            Assumes feed components are immutable configuration data. This helper does
    ///                 not call feed selectors or validate returned prices; callers that mutate
    ///                 configuration must validate price resolution after storing the candidate
    ///                 configuration.
    /// @dev            Will revert if:
    ///                 - No feeds are supplied
    ///                 - Any feed target submodule is not installed
    ///                 - Any feed component is duplicated
    ///
    /// @param asset_   Asset address for error reporting
    /// @param feeds_   Candidate price feed components
    function _validateAssetPriceFeeds(address asset_, Component[] memory feeds_) internal view {
        uint256 len = feeds_.length;
        if (len == 0) revert PRICE_ParamsPriceFeedInsufficient(asset_, len, 1);

        bytes32[] memory hashes = new bytes32[](len);

        for (uint256 i; i < len; ) {
            if (!_submoduleIsInstalled(feeds_[i].target))
                revert PRICE_SubmoduleNotInstalled(asset_, abi.encode(feeds_[i].target));

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
    }

    /// @notice             Validates the price strategy component for an asset configuration
    /// @dev                Treats a zero target as "no strategy" and otherwise checks that the
    ///                     strategy target submodule is installed.
    /// @dev                Assumes selector and params compatibility is proven when the configured
    ///                     strategy is used to resolve a price. This helper only validates the
    ///                     PRICE-owned invariant that configured strategy targets are installed.
    /// @dev                Will revert if:
    ///                     - A non-zero strategy target submodule is not installed
    ///
    /// @param asset_       Asset address for error reporting
    /// @param strategy_    Candidate price strategy component
    function _validateAssetPriceStrategy(address asset_, Component memory strategy_) internal view {
        if (
            fromSubKeycode(strategy_.target) != bytes20(0) &&
            !_submoduleIsInstalled(strategy_.target)
        ) revert PRICE_SubmoduleNotInstalled(asset_, abi.encode(strategy_.target));
    }

    /// @notice                             Validates moving-average storage parameters
    /// @dev                                Checks that disabled moving-average storage has no
    ///                                     residual moving-average parameters, and that enabled
    ///                                     storage has a valid duration, observation count,
    ///                                     timestamp, and non-zero observations.
    /// @dev                                Assumes `_observationFrequency` was validated by the
    ///                                     constructor and is non-zero. Observations are assumed to
    ///                                     be PRICE-scaled prices; this helper only rejects zero
    ///                                     observations and does not validate economic plausibility.
    /// @dev                                Will revert if:
    ///                                     - Moving-average storage is disabled but observations,
    ///                                       duration, or last observation time are non-zero
    ///                                     - Last observation time is in the future
    ///                                     - Duration is zero or not divisible by observation frequency
    ///                                     - Observation count does not match duration/frequency
    ///                                     - Fewer than two observations are supplied
    ///                                     - Any observation is zero
    ///
    /// @param asset_                       Asset address for error reporting
    /// @param storeMovingAverage_          Whether moving-average storage is enabled
    /// @param movingAverageDuration_       Candidate moving-average duration in seconds
    /// @param lastObservationTime_         Candidate last observation timestamp
    /// @param observations_                Candidate moving-average observations
    function _validateAssetMovingAverage(
        address asset_,
        bool storeMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) internal view {
        if (!storeMovingAverage_) {
            if (observations_.length != 0)
                revert PRICE_ParamsInvalidObservationCount(asset_, observations_.length, 0, 0);

            if (movingAverageDuration_ != 0)
                revert PRICE_ParamsMovingAverageDurationInvalid(asset_, movingAverageDuration_, 0);

            if (lastObservationTime_ != 0)
                revert PRICE_ParamsLastObservationTimeInvalid(asset_, lastObservationTime_, 0, 0);

            return;
        }

        uint48 currentTime = uint48(block.timestamp);
        if (lastObservationTime_ > currentTime)
            revert PRICE_ParamsLastObservationTimeInvalid(
                asset_,
                lastObservationTime_,
                0,
                currentTime
            );

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

        for (uint256 i; i < numObservations; ) {
            if (observations_[i] == 0) revert PRICE_ParamsObservationZero(asset_, i);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice                             Validates parameters for adding a new asset
    /// @dev                                Performs the reusable queue-time and mutation-time
    ///                                     validation for `addAsset()` and `validateAddAsset()`.
    /// @dev                                Assumes the caller will validate live price resolution
    ///                                     after writing the candidate configuration. This helper
    ///                                     validates structural PRICE invariants only; it does not
    ///                                     call feeds or strategies. It therefore does not validate
    ///                                     feed selector/params compatibility, strategy selector/params
    ///                                     compatibility, or whether a feed/strategy/moving-average
    ///                                     combination can resolve a non-zero price.
    /// @dev                                Will revert if:
    ///                                     - The asset is the reserved unit-of-account address
    ///                                     - The asset is neither a contract nor a registered
    ///                                       non-contract asset
    ///                                     - The asset is already approved
    ///                                     - Feed/strategy/moving-average configuration is invalid
    ///                                     - Any configured submodule target is not installed
    ///
    /// @param asset_                       Candidate asset address
    /// @param storeMovingAverage_          Whether moving-average storage is enabled
    /// @param useMovingAverage_            Whether the moving average is included in strategy input
    /// @param movingAverageDuration_       Candidate moving-average duration in seconds
    /// @param lastObservationTime_         Candidate last observation timestamp
    /// @param observations_                Candidate moving-average observations
    /// @param strategy_                    Candidate price strategy component
    /// @param feeds_                       Candidate price feed components
    function _validateAddAsset(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        Component memory strategy_,
        Component[] memory feeds_
    ) internal view {
        if (_isUnitOfAccount(asset_)) revert PRICE_AssetReserved(asset_);
        _validateAssetIsManageable(asset_);
        if (_assetData[asset_].approved) revert PRICE_AssetAlreadyApproved(asset_);

        _validateAssetConfiguration(
            asset_,
            strategy_,
            feeds_.length,
            useMovingAverage_,
            storeMovingAverage_
        );
        _validateAssetPriceStrategy(asset_, strategy_);
        _validateAssetPriceFeeds(asset_, feeds_);
        _validateAssetMovingAverage(
            asset_,
            storeMovingAverage_,
            movingAverageDuration_,
            lastObservationTime_,
            observations_
        );
    }

    /// @notice         Validates parameters for removing an asset
    /// @dev            Performs the reusable queue-time and mutation-time validation for
    ///                 `removeAsset()` and `validateRemoveAsset()`.
    /// @dev            Assumes removal deletes the complete asset configuration before the asset
    ///                 can be reused. This helper does not inspect feed, strategy, or observation
    ///                 data because approval status is the PRICE source of truth for an active
    ///                 asset configuration.
    /// @dev            Will revert if:
    ///                 - The asset is the reserved unit-of-account address
    ///                 - The asset is not approved
    ///
    /// @param asset_   Candidate asset address
    function _validateRemoveAsset(address asset_) internal view {
        if (_isUnitOfAccount(asset_)) revert PRICE_AssetReserved(asset_);
        if (!_assetData[asset_].approved) revert PRICE_AssetNotApproved(asset_);
    }

    /// @notice         Validates parameters for updating an existing asset
    /// @dev            Performs the reusable queue-time and mutation-time validation for
    ///                 `updateAsset()` and `validateUpdateAsset()`.
    /// @dev            Builds the final configuration from the current stored asset data plus
    ///                 flagged updates, then validates that final configuration atomically.
    /// @dev            Assumes unflagged stored components were validated when they were added or
    ///                 previously updated. This helper validates installed submodules only for
    ///                 components supplied in `params_`; stored components are trusted as current
    ///                 PRICE state.
    /// @dev            Assumes the caller will validate live price resolution after writing the
    ///                 candidate configuration. This helper validates structural PRICE invariants
    ///                 only; it does not call feeds or strategies. It therefore does not validate
    ///                 feed selector/params compatibility, strategy selector/params compatibility,
    ///                 or whether the final feed/strategy/moving-average combination can resolve a
    ///                 non-zero price.
    /// @dev            Will revert if:
    ///                 - The asset is the reserved unit-of-account address
    ///                 - The asset is neither a contract nor a registered non-contract asset
    ///                 - No update flags are set
    ///                 - The asset is not approved
    ///                 - The final feed/strategy/moving-average configuration is invalid
    ///                 - Any newly supplied submodule target is not installed
    ///
    /// @param asset_   Asset address to update
    /// @param params_  Candidate update parameters
    function _validateUpdateAsset(address asset_, UpdateAssetParams memory params_) internal view {
        if (_isUnitOfAccount(asset_)) revert PRICE_AssetReserved(asset_);
        _validateAssetIsManageable(asset_);

        if (!params_.updateFeeds && !params_.updateStrategy && !params_.updateMovingAverage)
            revert PRICE_NoUpdatesRequested(asset_);

        Asset storage asset = _assetData[asset_];
        if (!asset.approved) revert PRICE_AssetNotApproved(asset_);

        Component[] memory finalFeeds = params_.updateFeeds
            ? params_.feeds
            : abi.decode(asset.feeds, (Component[]));
        bool finalUseMA = params_.updateStrategy
            ? params_.useMovingAverage
            : asset.useMovingAverage;
        bool finalStoreMA = params_.updateMovingAverage
            ? params_.storeMovingAverage
            : asset.storeMovingAverage;

        _validateAssetConfiguration(
            asset_,
            params_.updateStrategy ? params_.strategy : abi.decode(asset.strategy, (Component)),
            finalFeeds.length,
            finalUseMA,
            finalStoreMA
        );

        if (params_.updateFeeds) _validateAssetPriceFeeds(asset_, params_.feeds);
        if (params_.updateStrategy) _validateAssetPriceStrategy(asset_, params_.strategy);
        if (params_.updateMovingAverage)
            _validateAssetMovingAverage(
                asset_,
                params_.storeMovingAverage,
                params_.movingAverageDuration,
                params_.lastObservationTime,
                params_.observations
            );
    }

    /// @inheritdoc IPRICEv2
    /// @dev            Performs structural validation only. This function does not call configured
    ///                 price feeds or strategies, and therefore does not prove that the supplied
    ///                 feed/strategy/moving-average configuration can resolve a non-zero price.
    function validateAddAsset(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        Component memory strategy_,
        Component[] memory feeds_
    ) external view override {
        _validateAddAsset(
            asset_,
            storeMovingAverage_,
            useMovingAverage_,
            movingAverageDuration_,
            lastObservationTime_,
            observations_,
            strategy_,
            feeds_
        );
    }

    /// @inheritdoc IPRICEv2
    function validateRemoveAsset(address asset_) external view override {
        _validateRemoveAsset(asset_);
    }

    /// @inheritdoc IPRICEv2
    /// @dev            Performs structural validation only. This function does not call configured
    ///                 price feeds or strategies, and therefore does not prove that the final
    ///                 feed/strategy/moving-average configuration can resolve a non-zero price.
    function validateUpdateAsset(
        address asset_,
        UpdateAssetParams memory params_
    ) external view override {
        _validateUpdateAsset(asset_, params_);
    }

    /// @inheritdoc IPRICEv2
    function validateInstallSubmodule(address submodule_) external view override {
        SubKeycode subKeycode = _validateSubmodule(Submodule(submodule_));
        if (address(getSubmoduleForKeycode[subKeycode]) != address(0))
            revert Module_SubmoduleAlreadyInstalled(subKeycode);
    }

    /// @inheritdoc IPRICEv2
    function validateUpgradeSubmodule(address submodule_) external view override {
        Submodule newSubmodule = Submodule(submodule_);
        SubKeycode subKeycode = _validateSubmodule(newSubmodule);
        Submodule oldSubmodule = getSubmoduleForKeycode[subKeycode];
        if (oldSubmodule == Submodule(address(0)) || oldSubmodule == newSubmodule)
            revert Module_InvalidSubmoduleUpgrade(subKeycode);
    }

    /// @inheritdoc IPRICEv2
    function validateExecOnSubmodule(bytes20 subKeycode_) external view override {
        _getSubmoduleIfInstalled(SubKeycode.wrap(subKeycode_));
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Performs basic checks on the parameters
    /// @dev        - Sets the price strategy using `_updateAssetPriceStrategy()`
    /// @dev        - Sets the price feeds using `_updateAssetPriceFeeds()`
    /// @dev        - Sets the moving average data using `_updateAssetMovingAverage()`
    /// @dev        - Validates the configuration using `_getCurrentPrice()` or, when using a moving average,
    /// @dev          both the raw observation and MA-inclusive CURRENT strategy input shapes
    /// @dev        - Adds the asset to the `assets` array and marks it as approved
    ///
    /// @dev        When `useMovingAverage_` is true, validation appends a synthetic moving-average value derived from the current raw feed observation.
    ///             If the last stored observation is out of consensus, call `storeObservation(asset_)` after adding the asset before consumers rely on CURRENT price reads.
    ///
    /// @dev        Will revert if:
    /// @dev        - The caller is not permissioned
    /// @dev        - `asset_` is neither a contract nor a registered non-contract asset
    /// @dev        - `asset_` is already approved
    /// @dev        - `asset_` is the reserved unit-of-account address
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
        _validateAddAsset(
            asset_,
            storeMovingAverage_,
            useMovingAverage_,
            movingAverageDuration_,
            lastObservationTime_,
            observations_,
            strategy_,
            feeds_
        );

        Asset storage asset = _assetData[asset_];

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

        // Validate configuration. Observation writes never include the moving average, so a
        // moving-average strategy must support raw feeds and raw feeds plus a synthetic MA value.
        bool successAllFeeds;
        if (useMovingAverage_) {
            _revertIfMovingAverageStale(asset_, asset.lastObservationTime);
            successAllFeeds = _validateMovingAverageStrategy(asset_);
        } else {
            (, , successAllFeeds) = _getCurrentPrice(asset_, true);
        }
        if (!successAllFeeds) revert PRICE_PriceFeedCallFailed(asset_);

        // Set asset as approved and add to array
        asset.approved = true;
        assets.push(asset_);

        // Emit event
        emit AssetAdded(asset_);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Will revert if:
    /// @dev        - `asset_` is the reserved unit-of-account address
    /// @dev        - `asset_` is not approved
    /// @dev        - The caller is not permissioned
    /// @dev        Reentrancy note: this function does not make external calls.
    function removeAsset(address asset_) external override permissioned {
        _validateRemoveAsset(asset_);

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
    /// @dev            - Sets the price feeds for the asset
    /// @dev            Assumes the caller has already validated `feeds_`.
    ///
    /// @param asset_   Asset to update the price feeds for
    /// @param feeds_   Array of price feed components
    function _updateAssetPriceFeeds(address asset_, Component[] memory feeds_) internal {
        _assetData[asset_].feeds = abi.encode(feeds_);
    }

    /// @notice                     Updates the price strategy for the asset
    /// @dev                        Implements the following logic:
    /// @dev                        - Sets the price strategy for the asset
    /// @dev                        - Sets the `useMovingAverage` flag for the asset
    /// @dev                        Assumes the caller has already validated `strategy_`.
    ///
    /// @param asset_               Asset to update the price strategy for
    /// @param strategy_            Price strategy component
    /// @param useMovingAverage_    Flag to indicate if the moving average should be used in the strategy
    function _updateAssetPriceStrategy(
        address asset_,
        Component memory strategy_,
        bool useMovingAverage_
    ) internal {
        // Update the asset price strategy
        _assetData[asset_].strategy = abi.encode(strategy_);

        // Update whether the strategy uses a moving average (should be checked that the moving average is stored for the asset prior to sending to this function)
        _assetData[asset_].useMovingAverage = useMovingAverage_;
    }

    /// @notice                         Updates the moving average data for the asset
    /// @dev                            Implements the following logic:
    /// @dev                            - Removes existing moving average data
    /// @dev                            - Sets the moving average data for the asset
    /// @dev                            - If `storeMovingAverage_` is false, clears moving-average state
    /// @dev                            Assumes the caller has already validated moving-average
    ///                                 duration, timestamps, and observations.
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

        // Remove existing moving average data, if any
        if (asset.obs.length > 0) delete asset.obs;

        asset.storeMovingAverage = storeMovingAverage_;
        asset.cumulativeObs = 0;
        asset.nextObsIndex = 0;

        if (!storeMovingAverage_) {
            // Clear moving-average fields.
            asset.movingAverageDuration = 0;
            asset.numObservations = 0;
            asset.lastObservationTime = 0;
            return;
        }

        uint16 numObservations = SafeCast.encodeUInt16(
            uint48(movingAverageDuration_) / _observationFrequency
        );

        asset.movingAverageDuration = movingAverageDuration_;
        asset.numObservations = numObservations;
        asset.lastObservationTime = lastObservationTime_;

        for (uint256 i; i < numObservations; ) {
            asset.cumulativeObs += observations_[i];
            asset.obs.push(observations_[i]);
            unchecked {
                ++i;
            }
        }

        uint256 lastObsPrice = observations_[numObservations - 1];

        // Emit Price Stored event for new observation
        emit PriceStored(asset_, lastObsPrice, lastObservationTime_);
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Implements the following logic:
    /// @dev        - Validates that at least one update flag is true
    /// @dev        - Validates that asset is approved
    /// @dev        - Calculates final state (before any updates)
    /// @dev        - Validates the final configuration atomically
    /// @dev        - Validates submodules are installed for updated components
    /// @dev        - Calls update functions for flagged updates
    /// @dev        - Validates final configuration with `_getCurrentPrice()` or, when using a moving average,
    /// @dev          both the raw observation and MA-inclusive CURRENT strategy input shapes
    /// @dev        - Emits events based on which updates occurred
    ///
    /// @dev        When the final configuration uses the moving average, validation appends a synthetic moving-average value derived from the current raw feed observation, in order to allow for re-configuration when the last observation is stale or out of consensus.
    ///             If the last stored observation is stale or out of consensus, call `storeObservation(asset_)` after updating the asset before consumers rely on CURRENT price reads.
    ///
    /// @dev        Will revert if:
    /// @dev        - All update flags are false (no-op)
    /// @dev        - `asset_` is the reserved unit-of-account address
    /// @dev        - `asset_` is not approved
    /// @dev        - The final configuration is invalid
    /// @dev        - Any updated submodule is not installed
    /// @dev        Reentrancy note: any external feed/strategy resolution in validation uses
    ///             `staticcall`, so callbacks cannot perform state-changing reentry.
    function updateAsset(
        address asset_,
        UpdateAssetParams memory params_
    ) external virtual override permissioned {
        _validateUpdateAsset(asset_, params_);

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

        // Validate final configuration atomically.
        // Observation writes never include the moving average, so a moving-average strategy must
        // support raw feeds and raw feeds plus a synthetic MA value. Use the synthetic value here
        // so a stale stored MA does not block governance reconfiguration.
        Asset storage asset = _assetData[asset_];
        bool successAllFeeds;
        if (asset.useMovingAverage) {
            successAllFeeds = _validateMovingAverageStrategy(asset_);
        } else {
            (, , successAllFeeds) = _getCurrentPrice(asset_, false);
        }
        if (!successAllFeeds) revert PRICE_PriceFeedCallFailed(asset_);

        // Emit events (based on which updates occurred)
        if (params_.updateFeeds) emit AssetPriceFeedsUpdated(asset_);
        if (params_.updateStrategy) emit AssetPriceStrategyUpdated(asset_);
        if (params_.updateMovingAverage) emit AssetMovingAverageUpdated(asset_);
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
