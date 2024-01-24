// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {FullMath} from "libraries/FullMath.sol";

/// @title      ChainlinkPriceFeeds
/// @author     0xJem
/// @notice     Provides prices derived from Chainlink price feed(s)
contract ChainlinkPriceFeeds is PriceSubmodule {
    using FullMath for uint256;

    /// @notice     Any token or pool with a decimal scale greater than this would result in an overflow
    uint8 internal constant BASE_10_MAX_EXPONENT = 50;

    /// @notice                 Parameters for a single Chainlink price feed
    ///
    /// @param feed             Address of the Chainlink price feed
    /// @param updateThreshold  The maximum number of seconds elapsed since the last price feed update
    struct OneFeedParams {
        AggregatorV2V3Interface feed;
        uint48 updateThreshold;
    }

    /// @notice                         Parameters for a two Chainlink price feeds
    ///
    /// @param firstFeed                First: Address of the Chainlink price feed
    /// @param firstUpdateThreshold     First: The maximum number of seconds elapsed since the last price feed update
    /// @param secondFeed               Second: Address of the Chainlink price feed
    /// @param secondUpdateThreshold    Second: The maximum number of seconds elapsed since the last price feed update
    struct TwoFeedParams {
        AggregatorV2V3Interface firstFeed;
        uint48 firstUpdateThreshold;
        AggregatorV2V3Interface secondFeed;
        uint48 secondUpdateThreshold;
    }

    /// @notice                         Struct to represent data returned by the Chainlink price feed
    struct FeedRoundData {
        uint80 roundId;
        int256 priceInt;
        uint256 startedAt;
        uint256 updatedAt;
    }

    // ========== ERRORS ========== //

    /// @notice                 The number of decimals of the price feed is greater than the maximum allowed
    ///
    /// @param feed_            The address of the price feed
    /// @param feedDecimals_    The number of decimals of the price feed
    /// @param maxDecimals_     The maximum number of decimals allowed
    error Chainlink_FeedDecimalsOutOfBounds(address feed_, uint8 feedDecimals_, uint8 maxDecimals_);

    /// @notice                 The price returned by the price feed is invalid
    /// @dev                    This could be because:
    /// @dev                    - The price is <= 0
    ///
    /// @param feed_            The address of the price feed
    /// @param price_           The price returned by the price feed
    error Chainlink_FeedPriceInvalid(address feed_, int256 price_);

    /// @notice                     The data returned by the price feed is stale
    /// @dev                        This could be because:
    /// @dev                        - The price feed was last updated before the update threshold
    ///
    /// @param feed_                The address of the price feed
    /// @param roundTimestamp_      The timestamp of the round returned by the price feed
    /// @param thresholdTimestamp_  The earliest acceptable timestamp
    error Chainlink_FeedRoundStale(
        address feed_,
        uint256 roundTimestamp_,
        uint256 thresholdTimestamp_
    );

    /// @notice                 A price feed specified in the parameters is invalid
    ///
    /// @param paramsIndex_     The index of the parameter
    /// @param feed_            The address of the price feed
    error Chainlink_ParamsFeedInvalid(uint8 paramsIndex_, address feed_);

    /// @notice                 An update threshold specified in the parameters is invalid
    /// @dev                    This currently occurs if the update threshold is 0
    ///
    /// @param paramsIndex_     The index of the parameter
    /// @param updateThreshold_ The update threshold
    error Chainlink_ParamsUpdateThresholdInvalid(uint8 paramsIndex_, uint48 updateThreshold_);

    /// @notice                 The price feed is invalid
    /// @dev                    This is triggered if the price feed reverted when called,
    /// @dev                    and indicates that the feed address is not a Chainlink price feed.
    ///
    /// @param feed_            The address of the price feed
    error Chainlink_FeedInvalid(address feed_);

    /// @notice                 The number of decimals to return the price in is greater than the maximum allowed
    ///
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @param maxDecimals_     The maximum number of decimals allowed
    error Chainlink_OutputDecimalsOutOfBounds(uint8 outputDecimals_, uint8 maxDecimals_);

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== KERNEL FUNCTIONS =========== //

    /// @inheritdoc      Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.CHAINLINK");
    }

    /// @inheritdoc      Submodule
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== PRICE FEED FUNCTIONS ========== //

    /// @notice                         Validates the result of the price feed
    /// @dev                            This function will revert if:
    /// @dev                            - Answer <= 0
    /// @dev                            - Updated at timestamp before the update threshold from the current time
    ///
    /// @param feed_                    Chainlink price feed
    /// @param roundData                The round data returned by the price feed
    /// @param blockTimestamp           The current block timestamp
    /// @param paramsUpdateThreshold    The maximum number of seconds elapsed since the last price feed update
    function _validatePriceFeedResult(
        AggregatorV2V3Interface feed_,
        FeedRoundData memory roundData,
        uint256 blockTimestamp,
        uint256 paramsUpdateThreshold
    ) internal pure {
        if (roundData.priceInt <= 0)
            revert Chainlink_FeedPriceInvalid(address(feed_), roundData.priceInt);

        if (roundData.updatedAt < blockTimestamp - paramsUpdateThreshold)
            revert Chainlink_FeedRoundStale(
                address(feed_),
                roundData.updatedAt,
                blockTimestamp - paramsUpdateThreshold
            );
    }

    /// @notice                         Retrieves the latest price returned by the specified Chainlink price feed.
    /// @dev                            The result is validated using `_validatePriceFeedResult`, and will revert if invalid
    ///
    /// @param feed_                    Chainlink price feed
    /// @param updateThreshold_         The maximum number of seconds elapsed since the last price feed update
    /// @param feedDecimals_            The number of decimals of the price feed
    /// @param outputDecimals_          The number of decimals to return the price in
    /// @return                         The validated price in the scale of `outputDecimals_`
    function _getFeedPrice(
        AggregatorV2V3Interface feed_,
        uint256 updateThreshold_,
        uint8 feedDecimals_,
        uint8 outputDecimals_
    ) internal view returns (uint256) {
        FeedRoundData memory roundData;
        {
            try feed_.latestRoundData() returns (
                uint80 roundId,
                int256 priceInt,
                uint256 startedAt,
                uint256 updatedAt,
                uint80
            ) {
                roundData = FeedRoundData(roundId, priceInt, startedAt, updatedAt);
            } catch (bytes memory) {
                revert Chainlink_FeedInvalid(address(feed_));
            }
        }
        _validatePriceFeedResult(feed_, roundData, block.timestamp, uint256(updateThreshold_));

        uint256 price = uint256(roundData.priceInt);

        return price.mulDiv(10 ** outputDecimals_, 10 ** feedDecimals_);
    }

    /// @notice                 Returns the price from a single Chainlink feed, as specified in `params_`.
    /// @dev                    This function will revert if:
    /// @dev                    - PRICE's priceDecimals or the feed's decimals are out of bounds and would lead to an overflow
    /// @dev                    - The price feed's results are invalid
    ///
    /// @param outputDecimals_  The number of output decimals (assumed to be the same as PRICE decimals)
    /// @param params_          Chainlink pool parameters of type `OneFeedParams`
    /// @return                 Price in the scale of `outputDecimals_`
    function getOneFeedPrice(
        address,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Decode params
        OneFeedParams memory params = abi.decode(params_, (OneFeedParams));
        if (address(params.feed) == address(0))
            revert Chainlink_ParamsFeedInvalid(0, address(params.feed));
        if (params.updateThreshold == 0)
            revert Chainlink_ParamsUpdateThresholdInvalid(1, params.updateThreshold);

        // Ensure that no decimals would result in an underflow or overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Chainlink_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);
        uint8 feedDecimals = params.feed.decimals();
        if (feedDecimals > BASE_10_MAX_EXPONENT)
            revert Chainlink_FeedDecimalsOutOfBounds(
                address(params.feed),
                feedDecimals,
                BASE_10_MAX_EXPONENT
            );

        uint256 feedPrice = _getFeedPrice(
            params.feed,
            uint256(params.updateThreshold),
            feedDecimals,
            outputDecimals_
        );

        return feedPrice;
    }

    /// @notice                 Returns the result of dividing the price from the first Chainlink feed by the price from the second.
    /// @dev                    For example, passing in ETH-DAI and USD-DAI will return the ETH-USD price.
    ///
    /// @dev                    This function will revert if:
    /// @dev                    - PRICE's priceDecimals or any of the feed's decimals are out of bounds and would lead to an overflow
    /// @dev                    - Any of the price feeds' results are invalid
    ///
    /// @param outputDecimals_  The number of output decimals (assumed to be the same as PRICE decimals)
    /// @param params_          Chainlink pool parameters of type `TwoFeedParams`
    /// @return                 Price in the scale of `outputDecimals_`.
    function getTwoFeedPriceDiv(
        address,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Decode params
        TwoFeedParams memory params = abi.decode(params_, (TwoFeedParams));
        if (address(params.firstFeed) == address(0))
            revert Chainlink_ParamsFeedInvalid(0, address(params.firstFeed));
        if (params.firstUpdateThreshold == 0)
            revert Chainlink_ParamsUpdateThresholdInvalid(1, params.firstUpdateThreshold);
        if (address(params.secondFeed) == address(0))
            revert Chainlink_ParamsFeedInvalid(2, address(params.secondFeed));
        if (params.secondUpdateThreshold == 0)
            revert Chainlink_ParamsUpdateThresholdInvalid(3, params.secondUpdateThreshold);

        // Ensure that no decimals would result in an underflow or overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Chainlink_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);
        uint8 firstFeedDecimals = params.firstFeed.decimals();
        if (firstFeedDecimals > BASE_10_MAX_EXPONENT)
            revert Chainlink_FeedDecimalsOutOfBounds(
                address(params.firstFeed),
                firstFeedDecimals,
                BASE_10_MAX_EXPONENT
            );
        uint8 secondFeedDecimals = params.secondFeed.decimals();
        if (secondFeedDecimals > BASE_10_MAX_EXPONENT)
            revert Chainlink_FeedDecimalsOutOfBounds(
                address(params.secondFeed),
                secondFeedDecimals,
                BASE_10_MAX_EXPONENT
            );

        // Get prices from feeds
        uint256 numeratorPrice = _getFeedPrice(
            params.firstFeed,
            uint256(params.firstUpdateThreshold),
            firstFeedDecimals,
            outputDecimals_
        );
        uint256 denominatorPrice = _getFeedPrice(
            params.secondFeed,
            uint256(params.secondUpdateThreshold),
            secondFeedDecimals,
            outputDecimals_
        );

        // Convert to numerator/denominator price and return
        uint256 priceResult = numeratorPrice.mulDiv(10 ** outputDecimals_, denominatorPrice);

        return priceResult;
    }

    /// @notice                 Returns the result of multiplying the price from the first Chainlink feed by the price from the second.
    /// @dev                    For example, passing in ETH-DAI and DAI-USD will return the ETH-USD price.
    ///
    /// @dev                    This function will revert if:
    /// @dev                   - PRICE's priceDecimals or any of the feed's decimals are out of bounds and would lead to an overflow
    /// @dev                   - Any of the price feeds' results are invalid
    ///
    /// @param outputDecimals_  The number of output decimals (assumed to be the same as PRICE decimals)
    /// @param params_          Chainlink pool parameters of type `TwoFeedParams`
    /// @return                 Price in the scale of `outputDecimals_`.
    function getTwoFeedPriceMul(
        address,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Decode params
        TwoFeedParams memory params = abi.decode(params_, (TwoFeedParams));
        if (address(params.firstFeed) == address(0))
            revert Chainlink_ParamsFeedInvalid(0, address(params.firstFeed));
        if (params.firstUpdateThreshold == 0)
            revert Chainlink_ParamsUpdateThresholdInvalid(1, params.firstUpdateThreshold);
        if (address(params.secondFeed) == address(0))
            revert Chainlink_ParamsFeedInvalid(2, address(params.secondFeed));
        if (params.secondUpdateThreshold == 0)
            revert Chainlink_ParamsUpdateThresholdInvalid(3, params.secondUpdateThreshold);

        // Ensure that no decimals would result in an underflow or overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Chainlink_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);
        uint8 firstFeedDecimals = params.firstFeed.decimals();
        if (firstFeedDecimals > BASE_10_MAX_EXPONENT)
            revert Chainlink_FeedDecimalsOutOfBounds(
                address(params.firstFeed),
                firstFeedDecimals,
                BASE_10_MAX_EXPONENT
            );
        uint8 secondFeedDecimals = params.secondFeed.decimals();
        if (secondFeedDecimals > BASE_10_MAX_EXPONENT)
            revert Chainlink_FeedDecimalsOutOfBounds(
                address(params.secondFeed),
                secondFeedDecimals,
                BASE_10_MAX_EXPONENT
            );

        // Get prices from feeds
        uint256 firstPrice = _getFeedPrice(
            params.firstFeed,
            uint256(params.firstUpdateThreshold),
            firstFeedDecimals,
            outputDecimals_
        );
        uint256 secondPrice = _getFeedPrice(
            params.secondFeed,
            uint256(params.secondUpdateThreshold),
            secondFeedDecimals,
            outputDecimals_
        );

        // Convert to first * second price and return
        uint256 priceResult = firstPrice.mulDiv(secondPrice, 10 ** outputDecimals_);

        return priceResult;
    }
}
