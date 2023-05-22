// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {FullMath} from "libraries/FullMath.sol";

contract ChainlinkPriceFeeds is PriceSubmodule {
    using FullMath for uint256;

    // 50 seems to be the maximum exponent that can be used without overflowing
    uint8 internal constant BASE_10_MAX_EXPONENT = 50;

    struct OneFeedParams {
        AggregatorV2V3Interface feed;
        uint48 updateThreshold;
    }

    struct TwoFeedParams {
        AggregatorV2V3Interface numeratorFeed;
        uint48 numeratorUpdateThreshold;
        AggregatorV2V3Interface denominatorFeed;
        uint48 denominatorUpdateThreshold;
    }

    struct FeedRoundData {
        uint80 roundId;
        int256 priceInt;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    // ========== ERRORS ========== //

    error Chainlink_FeedDecimalsOutOfBounds(address feed_);
    error Chainlink_FeedPriceInvalid(address feed_);
    error Chainlink_FeedRoundMismatch(address feed_);
    error Chainlink_FeedRoundStale(address feed_);
    error Chainlink_PRICEDecimalsOutOfBounds(address price_);

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== KERNEL FUNCTIONS =========== //

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.CHAINLINK");
    }

    // ========== PRICE FEED FUNCTIONS ========== //

    /// @notice Validates the result of the price feed
    /// @dev This function will revert if:
    /// - Answer <= 0
    /// - Updated at timestamp before the update threshold from the current time
    /// - Answered in round ID different to the round ID
    ///
    /// @param feed_ Chainlink price feed
    /// @param roundData The round data returned by the price feed
    /// @param blockTimestamp The current block timestamp
    /// @param paramsUpdateThreshold The maximum number of seconds elapsed since the last price feed update
    function _validatePriceFeedResult(
        AggregatorV2V3Interface feed_,
        FeedRoundData memory roundData,
        uint256 blockTimestamp,
        uint256 paramsUpdateThreshold
    ) internal pure {
        if (roundData.priceInt <= 0) revert Chainlink_FeedPriceInvalid(address(feed_));

        if (roundData.updatedAt < blockTimestamp - paramsUpdateThreshold)
            revert Chainlink_FeedRoundStale(address(feed_));

        if (roundData.answeredInRound != roundData.roundId)
            revert Chainlink_FeedRoundMismatch(address(feed_));
    }

    /// @notice Retrieves the latest price returned by the specified Chainlink price feed.
    /// @dev The result is validated using _validatePriceFeedResult, and will revert if invalid
    ///
    /// @param feed_ Chainlink price feed
    /// @param updateThreshold_ The maximum number of seconds elapsed since the last price feed update
    /// @return The validated price in the scale of PRICE's priceDecimals
    function _getFeedPrice(
        AggregatorV2V3Interface feed_,
        uint256 updateThreshold_
    ) internal view returns (uint256) {
        uint256 price;
        {
            FeedRoundData memory roundData;
            {
                (
                    uint80 roundId,
                    int256 priceInt,
                    uint256 startedAt,
                    uint256 updatedAt,
                    uint80 answeredInRound
                ) = feed_.latestRoundData();
                roundData.roundId = roundId;
                roundData.priceInt = priceInt;
                roundData.startedAt = startedAt;
                roundData.updatedAt = updatedAt;
                roundData.answeredInRound = answeredInRound;
            }
            {
                _validatePriceFeedResult(
                    feed_,
                    roundData,
                    block.timestamp,
                    uint256(updateThreshold_)
                );

                price = uint256(roundData.priceInt);
            }
        }

        uint256 priceAdjusted = price.mulDiv(10 ** _PRICE().decimals(), 10 ** feed_.decimals());
        return priceAdjusted;
    }

    /// @notice Returns the price from a single Chainlink feed, as specified in {params_}.
    /// @dev This function will revert if:
    /// - PRICE's priceDecimals or the feed's decimals are out of bounds and would lead to an overflow
    /// - The price feed's results are invalid
    ///
    /// @param params_ Chainlink pool parameters of type OneFeedParams
    /// @return uint256 Price in the scale of PRICE's priceDecimals.
    function getOneFeedPrice(bytes calldata params_) external view returns (uint256) {
        // Decode params
        OneFeedParams memory params = abi.decode(params_, (OneFeedParams));

        // Ensure that no decimals would result in an underflow or overflow
        uint8 priceDecimals = _PRICE().decimals();
        if (priceDecimals > BASE_10_MAX_EXPONENT)
            revert Chainlink_PRICEDecimalsOutOfBounds(address(_PRICE()));
        if (params.feed.decimals() > BASE_10_MAX_EXPONENT)
            revert Chainlink_FeedDecimalsOutOfBounds(address(params.feed));

        uint256 feedPrice = _getFeedPrice(params.feed, uint256(params.updateThreshold));

        return feedPrice;
    }

    /// @notice Returns the result of dividing the price from the first Chainlink feed by the price from the second.
    /// @dev For example, passing in ETH-DAI and USD-DAI will return the ETH-USD price.
    ///
    /// This function will revert if:
    /// - PRICE's priceDecimals or any of the feed's decimals are out of bounds and would lead to an overflow
    /// - Any of the price feeds' results are invalid
    ///
    /// @param params_ Chainlink pool parameters of type TwoFeedParams
    /// @return uint256 Price in the scale of PRICE's priceDecimals.
    function getTwoFeedPriceDiv(bytes calldata params_) external view returns (uint256) {
        // Decode params
        TwoFeedParams memory params = abi.decode(params_, (TwoFeedParams));

        // Ensure that no decimals would result in an underflow or overflow
        uint8 priceDecimals = _PRICE().decimals();
        if (priceDecimals > BASE_10_MAX_EXPONENT)
            revert Chainlink_PRICEDecimalsOutOfBounds(address(_PRICE()));
        if (params.numeratorFeed.decimals() > BASE_10_MAX_EXPONENT)
            revert Chainlink_FeedDecimalsOutOfBounds(address(params.numeratorFeed));
        if (params.denominatorFeed.decimals() > BASE_10_MAX_EXPONENT)
            revert Chainlink_FeedDecimalsOutOfBounds(address(params.denominatorFeed));

        // Get prices from feeds
        uint256 numeratorPrice = _getFeedPrice(
            params.numeratorFeed,
            uint256(params.numeratorUpdateThreshold)
        );
        uint256 denominatorPrice = _getFeedPrice(
            params.denominatorFeed,
            uint256(params.denominatorUpdateThreshold)
        );

        // Convert to numerator/denominator price and return
        uint256 priceResult = numeratorPrice.mulDiv(10 ** priceDecimals, denominatorPrice);

        return priceResult;
    }

    /// @notice Returns the result of multiplying the price from the first Chainlink feed by the price from the second.
    /// @dev For example, passing in ETH-DAI and DAI-USD will return the ETH-USD price.
    ///
    /// This function will revert if:
    /// - PRICE's priceDecimals or any of the feed's decimals are out of bounds and would lead to an overflow
    /// - Any of the price feeds' results are invalid
    ///
    /// @param params_ Chainlink pool parameters of type TwoFeedParams
    /// @return uint256 Price in the scale of PRICE's priceDecimals.
    function getTwoFeedPriceMul(bytes calldata params_) external view returns (uint256) {
        // Decode params
        TwoFeedParams memory params = abi.decode(params_, (TwoFeedParams));

        // Ensure that no decimals would result in an underflow or overflow
        uint8 priceDecimals = _PRICE().decimals();
        if (priceDecimals > BASE_10_MAX_EXPONENT)
            revert Chainlink_PRICEDecimalsOutOfBounds(address(_PRICE()));
        if (params.numeratorFeed.decimals() > BASE_10_MAX_EXPONENT)
            revert Chainlink_FeedDecimalsOutOfBounds(address(params.numeratorFeed));
        if (params.denominatorFeed.decimals() > BASE_10_MAX_EXPONENT)
            revert Chainlink_FeedDecimalsOutOfBounds(address(params.denominatorFeed));

        // Get prices from feeds
        uint256 numeratorPrice = _getFeedPrice(
            params.numeratorFeed,
            uint256(params.numeratorUpdateThreshold)
        );
        uint256 denominatorPrice = _getFeedPrice(
            params.denominatorFeed,
            uint256(params.denominatorUpdateThreshold)
        );

        // Convert to numerator * denominator price and return
        uint256 priceResult = numeratorPrice.mulDiv(denominatorPrice, 10 ** priceDecimals);

        // Convert to numerator * denominator price and return
        return priceResult;
    }
}
