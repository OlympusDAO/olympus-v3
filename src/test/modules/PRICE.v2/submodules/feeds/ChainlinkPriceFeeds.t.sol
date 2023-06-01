// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockPrice} from "test/mocks/MockPrice.v2.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {FullMath} from "libraries/FullMath.sol";

import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import "src/Kernel.sol";
import {MockBalancerPool} from "test/mocks/MockBalancerPool.sol";

contract ChainlinkPriceFeedsTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for ChainlinkPriceFeeds;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal daiEthPriceFeed;
    MockPriceFeed internal ethDaiPriceFeed;

    Kernel internal kernel;
    MockPrice internal mockPrice;
    ChainlinkPriceFeeds internal chainlinkSubmodule;
    uint256 internal constant ohmEthPrice = 0.01 * 1e18; // 1 OHM = 0.01 ETH
    uint256 internal constant daiEthPrice = 0.001 * 1e18; // 1 DAI = 0.001 ETH
    uint256 internal constant ethDaiPrice = 1000 * 1e18; // 1 ETH = 1000 DAI

    // 0.01 ETH/OHM and 0.001 ETH/DAI = 0.01 ETH/OHM * (1/0.001) DAI/ETH = 10 DAI/OHM
    uint256 internal constant ohmDaiPrice = 10 * 1e18;

    uint8 internal constant MIN_DECIMALS = 6;
    uint8 internal constant MAX_DECIMALS = 50;

    uint48 internal constant UPDATE_THRESHOLD = 100;

    uint8 internal constant PRICE_DECIMALS = 18;

    uint8 internal constant PRICE_FEED_DECIMALS = 18;
    uint80 internal constant PRICE_FEED_ROUND_ID = 10;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Set up the Chainlink submodule
        {
            // Deploy kernel
            kernel = new Kernel();

            // Deploy mockPrice
            mockPrice = new MockPrice(kernel, uint8(18), uint32(8 hours));
            mockPrice.setTimestamp(uint48(block.timestamp));
            mockPrice.setPriceDecimals(PRICE_DECIMALS);

            // Deploy Chainlink submodule
            chainlinkSubmodule = new ChainlinkPriceFeeds(mockPrice);
        }

        // Set up the price feeds
        {
            ohmEthPriceFeed = new MockPriceFeed();
            ohmEthPriceFeed.setTimestamp(block.timestamp);
            ohmEthPriceFeed.setLatestAnswer(int256(ohmEthPrice));
            ohmEthPriceFeed.setDecimals(PRICE_FEED_DECIMALS);
            ohmEthPriceFeed.setRoundId(PRICE_FEED_ROUND_ID);
            ohmEthPriceFeed.setAnsweredInRound(PRICE_FEED_ROUND_ID);

            daiEthPriceFeed = new MockPriceFeed();
            daiEthPriceFeed.setTimestamp(block.timestamp);
            daiEthPriceFeed.setLatestAnswer(int256(daiEthPrice));
            daiEthPriceFeed.setDecimals(PRICE_FEED_DECIMALS);
            daiEthPriceFeed.setRoundId(PRICE_FEED_ROUND_ID);
            daiEthPriceFeed.setAnsweredInRound(PRICE_FEED_ROUND_ID);

            ethDaiPriceFeed = new MockPriceFeed();
            ethDaiPriceFeed.setTimestamp(block.timestamp);
            ethDaiPriceFeed.setLatestAnswer(int256(ethDaiPrice));
            ethDaiPriceFeed.setDecimals(PRICE_FEED_DECIMALS);
            ethDaiPriceFeed.setRoundId(PRICE_FEED_ROUND_ID);
            ethDaiPriceFeed.setAnsweredInRound(PRICE_FEED_ROUND_ID);
        }
    }

    // =========  HELPER METHODS ========= //

    function encodeOneFeedParams(
        AggregatorV2V3Interface feed,
        uint48 updateThreshold
    ) internal pure returns (bytes memory params) {
        return abi.encode(feed, updateThreshold);
    }

    function encodeTwoFeedParams(
        AggregatorV2V3Interface numeratorFeed,
        uint48 numeratorUpdateThreshold,
        AggregatorV2V3Interface denominatorFeed,
        uint48 denominatorUpdateThreshold
    ) internal pure returns (bytes memory params) {
        return
            abi.encode(
                numeratorFeed,
                numeratorUpdateThreshold,
                denominatorFeed,
                denominatorUpdateThreshold
            );
    }

    // =========  ONE FEED TESTS ========= //

    function test_getOneFeedPrice_success() public {
        bytes memory params = encodeOneFeedParams(daiEthPriceFeed, UPDATE_THRESHOLD);
        uint256 priceInt = chainlinkSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        assertEq(daiEthPrice, priceInt);
    }

    function test_getOneFeedPrice_revertsOnIncorrectFeedType() public {
        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedInvalid.selector,
            address(mockNonWeightedPool)
        );
        vm.expectRevert(err);

        bytes memory params = abi.encode(mockNonWeightedPool, UPDATE_THRESHOLD);
        chainlinkSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getOneFeedPrice_revertsOnParamsFeedUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_ParamsFeedInvalid.selector,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(
            AggregatorV2V3Interface(address(0)),
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getOneFeedPrice_revertsOnParamsThresholdUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_ParamsUpdateThresholdInvalid.selector,
            1,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(daiEthPriceFeed, 0);
        chainlinkSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getOneFeedPrice_revertsOnInvalidPriceFuzz(int256 latestAnswer_) public {
        int256 latestAnswer = bound(latestAnswer_, int256(type(int256).min), int256(0));
        daiEthPriceFeed.setLatestAnswer(latestAnswer);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedPriceInvalid.selector,
            address(daiEthPriceFeed),
            latestAnswer
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(daiEthPriceFeed, UPDATE_THRESHOLD);
        chainlinkSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getOneFeedPrice_roundFuzz(uint256 timestamp_) public {
        /**
         * If roundData.updatedAt (priceFeed.timestamp) < blockTimestamp - paramsUpdateThreshold,
         * then the price feed is considered stale and the function should revert.
         */
        // Mock timestamp at/above the threshold
        uint256 timestamp = bound(
            timestamp_,
            block.timestamp - UPDATE_THRESHOLD,
            type(uint256).max
        );
        daiEthPriceFeed.setTimestamp(timestamp);

        bytes memory params = encodeOneFeedParams(daiEthPriceFeed, UPDATE_THRESHOLD);
        uint256 priceInt = chainlinkSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        assertEq(daiEthPrice, priceInt);
    }

    function test_getOneFeedPrice_revertsOnStaleRoundFuzz(uint256 timestamp_) public {
        /**
         * If roundData.updatedAt (priceFeed.timestamp) < blockTimestamp - paramsUpdateThreshold,
         * then the price feed is considered stale and the function should revert.
         */
        // Mock timestamp below the threshold
        uint256 timestamp = bound(timestamp_, 0, block.timestamp - UPDATE_THRESHOLD - 1);
        daiEthPriceFeed.setTimestamp(timestamp);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedRoundStale.selector,
            address(daiEthPriceFeed),
            timestamp,
            block.timestamp - UPDATE_THRESHOLD
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(daiEthPriceFeed, UPDATE_THRESHOLD);
        chainlinkSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getOneFeedPrice_roundIdValid() public {
        // Mock answeredInRound = roundId
        daiEthPriceFeed.setRoundId(PRICE_FEED_ROUND_ID);
        daiEthPriceFeed.setAnsweredInRound(PRICE_FEED_ROUND_ID);

        bytes memory params = encodeOneFeedParams(daiEthPriceFeed, UPDATE_THRESHOLD);
        uint256 priceInt = chainlinkSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        assertEq(daiEthPrice, priceInt);
    }

    function test_getOneFeedPrice_revertsOnRoundIdMismatchFuzz(uint80 roundId_) public {
        uint80 roundId = uint80(bound(roundId_, 0, type(uint80).max));
        vm.assume(roundId != PRICE_FEED_ROUND_ID);

        // Mock answeredInRound > roundId
        daiEthPriceFeed.setRoundId(roundId);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedRoundMismatch.selector,
            address(daiEthPriceFeed),
            roundId,
            PRICE_FEED_ROUND_ID
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(daiEthPriceFeed, UPDATE_THRESHOLD);
        chainlinkSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getOneFeedPrice_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        bytes memory params = encodeOneFeedParams(daiEthPriceFeed, UPDATE_THRESHOLD);
        uint256 priceInt = chainlinkSubmodule.getOneFeedPrice(address(0), priceDecimals, params);

        assertEq(priceInt, 10 ** priceDecimals / 10 ** 3); // 0.001
    }

    function test_getOneFeedPrice_revertsOnPriceDecimalsMaximum() public {
        uint8 priceDecimals = MAX_DECIMALS + 1;

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_OutputDecimalsOutOfBounds.selector,
            priceDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(daiEthPriceFeed, UPDATE_THRESHOLD);
        chainlinkSubmodule.getOneFeedPrice(address(0), priceDecimals, params);
    }

    function test_getOneFeedPrice_priceFeedDecimalsFuzz(uint8 priceFeedDecimals_) public {
        uint8 priceFeedDecimals = uint8(bound(priceFeedDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        daiEthPriceFeed.setDecimals(priceFeedDecimals);
        daiEthPriceFeed.setLatestAnswer(
            int256(daiEthPrice.mulDiv(10 ** priceFeedDecimals, 10 ** PRICE_DECIMALS))
        );

        bytes memory params = encodeOneFeedParams(daiEthPriceFeed, UPDATE_THRESHOLD);
        uint256 priceInt = chainlinkSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        assertEq(priceInt, 10 ** PRICE_DECIMALS / 10 ** 3); // 0.001
    }

    function test_getOneFeedPrice_revertsOnPriceFeedDecimalsMaximum() public {
        // Force an overflow for any calculations involving the decimals
        daiEthPriceFeed.setDecimals(MAX_DECIMALS + 1);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedDecimalsOutOfBounds.selector,
            address(daiEthPriceFeed),
            MAX_DECIMALS + 1,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(daiEthPriceFeed, UPDATE_THRESHOLD);
        chainlinkSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // =========  TWO FEED TESTS - DIV ========= //

    function test_getTwoFeedPriceDiv_success() public {
        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceDiv(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, ohmDaiPrice);
    }

    function test_getTwoFeedPriceDiv_revertsOnParamsNumeratorFeedUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_ParamsFeedInvalid.selector,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            AggregatorV2V3Interface(address(0)),
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_revertsOnParamsNumeratorUpdateThresholdUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_ParamsUpdateThresholdInvalid.selector,
            1,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            0,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_revertsOnParamsDenominatorFeedUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_ParamsFeedInvalid.selector,
            2,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            AggregatorV2V3Interface(address(0)),
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_revertsOnParamsDenominatorUpdateThresholdUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_ParamsUpdateThresholdInvalid.selector,
            3,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            0
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_revertsOnNumeratorIncorrectFeedType() public {
        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedInvalid.selector,
            address(mockNonWeightedPool)
        );
        vm.expectRevert(err);

        bytes memory params = abi.encode(
            mockNonWeightedPool,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_revertsOnDenominatorIncorrectFeedType() public {
        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedInvalid.selector,
            address(mockNonWeightedPool)
        );
        vm.expectRevert(err);

        bytes memory params = abi.encode(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            mockNonWeightedPool,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_revertsOnInvalidNumeratorPriceFuzz(
        int256 latestAnswer_
    ) public {
        int256 latestAnswer = bound(latestAnswer_, int256(type(int256).min), int256(0));
        ohmEthPriceFeed.setLatestAnswer(latestAnswer);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedPriceInvalid.selector,
            address(ohmEthPriceFeed),
            latestAnswer
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_revertsOnInvalidDenominatorPriceFuzz(
        int256 latestAnswer_
    ) public {
        int256 latestAnswer = bound(latestAnswer_, int256(type(int256).min), int256(0));
        daiEthPriceFeed.setLatestAnswer(latestAnswer);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedPriceInvalid.selector,
            address(daiEthPriceFeed),
            latestAnswer
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_numeratorRoundTimestampFuzz(uint256 timestamp_) public {
        /**
         * If roundData.updatedAt (priceFeed.timestamp) < blockTimestamp - paramsUpdateThreshold,
         * then the price feed is considered stale and the function should revert.
         */
        // Mock timestamp at/above the threshold
        uint256 timestamp = bound(
            timestamp_,
            block.timestamp - UPDATE_THRESHOLD,
            type(uint256).max
        );
        ohmEthPriceFeed.setTimestamp(timestamp);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceDiv(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, ohmDaiPrice);
    }

    function test_getTwoFeedPriceDiv_revertsOnStaleNumeratorRoundTimestampFuzz(
        uint256 timestamp_
    ) public {
        /**
         * If roundData.updatedAt (priceFeed.timestamp) < blockTimestamp - paramsUpdateThreshold,
         * then the price feed is considered stale and the function should revert.
         */
        // Mock timestamp below the threshold
        uint256 timestamp = bound(timestamp_, 0, block.timestamp - UPDATE_THRESHOLD - 1);
        ohmEthPriceFeed.setTimestamp(timestamp);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedRoundStale.selector,
            address(ohmEthPriceFeed),
            timestamp,
            block.timestamp - UPDATE_THRESHOLD
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_denominatorRoundTimestampFuzz(uint256 timestamp_) public {
        /**
         * If roundData.updatedAt (priceFeed.timestamp) < blockTimestamp - paramsUpdateThreshold,
         * then the price feed is considered stale and the function should revert.
         */
        // Mock timestamp at/above the threshold
        uint256 timestamp = bound(
            timestamp_,
            block.timestamp - UPDATE_THRESHOLD,
            type(uint256).max
        );
        daiEthPriceFeed.setTimestamp(timestamp);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceDiv(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, ohmDaiPrice);
    }

    function test_getTwoFeedPriceDiv_revertsOnStaleDenominatorRoundTimestampFuzz(
        uint256 timestamp_
    ) public {
        /**
         * If roundData.updatedAt (priceFeed.timestamp) < blockTimestamp - paramsUpdateThreshold,
         * then the price feed is considered stale and the function should revert.
         */
        // Mock timestamp below the threshold
        uint256 timestamp = bound(timestamp_, 0, block.timestamp - UPDATE_THRESHOLD - 1);
        daiEthPriceFeed.setTimestamp(timestamp);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedRoundStale.selector,
            address(daiEthPriceFeed),
            timestamp,
            block.timestamp - UPDATE_THRESHOLD
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_numeratorRoundIdValid() public {
        // Mock answeredInRound = roundId
        ohmEthPriceFeed.setRoundId(PRICE_FEED_ROUND_ID);
        ohmEthPriceFeed.setAnsweredInRound(PRICE_FEED_ROUND_ID);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceDiv(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, ohmDaiPrice);
    }

    function test_getTwoFeedPriceDiv_revertsOnNumeratorRoundIdMismatchFuzz(uint80 roundId_) public {
        uint80 roundId = uint80(bound(roundId_, 0, type(uint80).max));
        vm.assume(roundId != PRICE_FEED_ROUND_ID);

        // Mock answeredInRound > roundId
        ohmEthPriceFeed.setRoundId(roundId);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedRoundMismatch.selector,
            address(ohmEthPriceFeed),
            roundId,
            PRICE_FEED_ROUND_ID
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_denominatorRoundIdValid() public {
        // Mock answeredInRound = roundId
        daiEthPriceFeed.setRoundId(PRICE_FEED_ROUND_ID);
        daiEthPriceFeed.setAnsweredInRound(PRICE_FEED_ROUND_ID);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceDiv(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, ohmDaiPrice);
    }

    function test_getTwoFeedPriceDiv_revertsOnDenominatorRoundIdMismatchFuzz(
        uint80 roundId_
    ) public {
        uint80 roundId = uint80(bound(roundId_, 0, type(uint80).max));
        vm.assume(roundId != PRICE_FEED_ROUND_ID);

        // Mock answeredInRound > roundId
        daiEthPriceFeed.setRoundId(roundId);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedRoundMismatch.selector,
            address(daiEthPriceFeed),
            roundId,
            PRICE_FEED_ROUND_ID
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_fuzz(
        uint8 priceFeedOneDecimals_,
        uint8 priceFeedTwoDecimals_,
        uint8 priceDecimals_
    ) public {
        uint8 priceFeedOneDecimals = uint8(
            bound(priceFeedOneDecimals_, MIN_DECIMALS, MAX_DECIMALS)
        );
        uint8 priceFeedTwoDecimals = uint8(
            bound(priceFeedTwoDecimals_, MIN_DECIMALS, MAX_DECIMALS)
        );
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        ohmEthPriceFeed.setLatestAnswer(
            int256(ohmEthPrice.mulDiv(10 ** priceFeedOneDecimals, 10 ** PRICE_DECIMALS))
        );
        ohmEthPriceFeed.setDecimals(priceFeedOneDecimals);
        daiEthPriceFeed.setLatestAnswer(
            int256(daiEthPrice.mulDiv(10 ** priceFeedTwoDecimals, 10 ** PRICE_DECIMALS))
        );
        daiEthPriceFeed.setDecimals(priceFeedTwoDecimals);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceDiv(address(0), priceDecimals, params);

        assertEq(priceInt, 10 * 10 ** priceDecimals); // Expected price is 10, adjusted with decimals
    }

    function test_getTwoFeedPriceDiv_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceDiv(address(0), priceDecimals, params);

        assertEq(priceInt, 10 * 10 ** priceDecimals); // Expected price is 10, adjusted with decimals
    }

    function test_getTwoFeedPriceDiv_revertsOnPriceDecimalsMaximum() public {
        uint8 priceDecimals = MAX_DECIMALS + 1;

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_OutputDecimalsOutOfBounds.selector,
            priceDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), priceDecimals, params);
    }

    function test_getTwoFeedPriceDiv_priceFeedDecimalsFuzz(
        uint8 priceFeedOneDecimals_,
        uint8 priceFeedTwoDecimals_
    ) public {
        uint8 priceFeedOneDecimals = uint8(
            bound(priceFeedOneDecimals_, MIN_DECIMALS, MAX_DECIMALS)
        );
        uint8 priceFeedTwoDecimals = uint8(
            bound(priceFeedTwoDecimals_, MIN_DECIMALS, MAX_DECIMALS)
        );

        ohmEthPriceFeed.setLatestAnswer(
            int256(ohmEthPrice.mulDiv(10 ** priceFeedOneDecimals, 10 ** PRICE_DECIMALS))
        );
        ohmEthPriceFeed.setDecimals(priceFeedOneDecimals);
        daiEthPriceFeed.setLatestAnswer(
            int256(daiEthPrice.mulDiv(10 ** priceFeedTwoDecimals, 10 ** PRICE_DECIMALS))
        );
        daiEthPriceFeed.setDecimals(priceFeedTwoDecimals);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceDiv(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, 10 * 10 ** PRICE_DECIMALS); // Expected price is 10, adjusted with decimals
    }

    function test_getTwoFeedPriceDiv_revertsOnNumeratorDecimalsMaximum() public {
        ohmEthPriceFeed.setDecimals(255);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedDecimalsOutOfBounds.selector,
            address(ohmEthPriceFeed),
            255,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceDiv_revertsOnDenominatorDecimalsMaximum() public {
        daiEthPriceFeed.setDecimals(255);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedDecimalsOutOfBounds.selector,
            address(daiEthPriceFeed),
            255,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // =========  TWO FEED TESTS - MUL ========= //

    function test_getTwoFeedPriceMul_success() public {
        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceMul(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, ohmDaiPrice);
    }

    function test_getTwoFeedPriceMul_revertsOnParamsNumeratorFeedUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_ParamsFeedInvalid.selector,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            AggregatorV2V3Interface(address(0)),
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_revertsOnParamsNumeratorUpdateThresholdUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_ParamsUpdateThresholdInvalid.selector,
            1,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            0,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_revertsOnParamsDenominatorFeedUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_ParamsFeedInvalid.selector,
            2,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            AggregatorV2V3Interface(address(0)),
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_revertsOnParamsDenominatorUpdateThresholdUndefined() public {
        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_ParamsUpdateThresholdInvalid.selector,
            3,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            0
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_revertsOnNumeratorIncorrectFeedType() public {
        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedInvalid.selector,
            address(mockNonWeightedPool)
        );
        vm.expectRevert(err);

        bytes memory params = abi.encode(
            mockNonWeightedPool,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_revertsOnDenominatorIncorrectFeedType() public {
        // Set up a non-weighted pool
        MockBalancerPool mockNonWeightedPool = new MockBalancerPool();
        mockNonWeightedPool.setDecimals(18);
        mockNonWeightedPool.setTotalSupply(1e8);
        mockNonWeightedPool.setPoolId(
            0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
        );

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedInvalid.selector,
            address(mockNonWeightedPool)
        );
        vm.expectRevert(err);

        bytes memory params = abi.encode(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            mockNonWeightedPool,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_revertsOnInvalidNumeratorPriceFuzz(
        int256 latestAnswer_
    ) public {
        int256 latestAnswer = bound(latestAnswer_, int256(type(int256).min), int256(0));
        ohmEthPriceFeed.setLatestAnswer(latestAnswer);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedPriceInvalid.selector,
            address(ohmEthPriceFeed),
            latestAnswer
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_revertsOnInvalidDenominatorPriceFuzz(
        int256 latestAnswer_
    ) public {
        int256 latestAnswer = bound(latestAnswer_, int256(type(int256).min), int256(0));
        ethDaiPriceFeed.setLatestAnswer(latestAnswer);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedPriceInvalid.selector,
            address(ethDaiPriceFeed),
            latestAnswer
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_numeratorRoundFuzz(uint256 timestamp_) public {
        /**
         * If roundData.updatedAt (priceFeed.timestamp) < blockTimestamp - paramsUpdateThreshold,
         * then the price feed is considered stale and the function should revert.
         */
        // Mock timestamp at/above the threshold
        uint256 timestamp = bound(
            timestamp_,
            block.timestamp - UPDATE_THRESHOLD,
            type(uint256).max
        );
        ohmEthPriceFeed.setTimestamp(timestamp);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceMul(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, ohmDaiPrice);
    }

    function test_getTwoFeedPriceMul_revertsOnStaleNumeratorRoundFuzz(uint256 timestamp_) public {
        /**
         * If roundData.updatedAt (priceFeed.timestamp) < blockTimestamp - paramsUpdateThreshold,
         * then the price feed is considered stale and the function should revert.
         */
        // Mock timestamp below the threshold
        uint256 timestamp = bound(timestamp_, 0, block.timestamp - UPDATE_THRESHOLD - 1);
        ohmEthPriceFeed.setTimestamp(timestamp);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedRoundStale.selector,
            address(ohmEthPriceFeed),
            timestamp,
            block.timestamp - UPDATE_THRESHOLD
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_denominatorRoundFuzz(uint256 timestamp_) public {
        /**
         * If roundData.updatedAt (priceFeed.timestamp) < blockTimestamp - paramsUpdateThreshold,
         * then the price feed is considered stale and the function should revert.
         */
        // Mock timestamp at/above the threshold
        uint256 timestamp = bound(
            timestamp_,
            block.timestamp - UPDATE_THRESHOLD,
            type(uint256).max
        );
        ethDaiPriceFeed.setTimestamp(timestamp);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceMul(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, ohmDaiPrice);
    }

    function test_getTwoFeedPriceMul_revertsOnStaleDenominatorRoundFuzz(uint256 timestamp_) public {
        /**
         * If roundData.updatedAt (priceFeed.timestamp) < blockTimestamp - paramsUpdateThreshold,
         * then the price feed is considered stale and the function should revert.
         */
        // Mock timestamp below the threshold
        uint256 timestamp = bound(timestamp_, 0, block.timestamp - UPDATE_THRESHOLD - 1);
        ethDaiPriceFeed.setTimestamp(timestamp);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedRoundStale.selector,
            address(ethDaiPriceFeed),
            timestamp,
            block.timestamp - UPDATE_THRESHOLD
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_numeratorRoundIdValid() public {
        // Mock answeredInRound = roundId
        ohmEthPriceFeed.setRoundId(PRICE_FEED_ROUND_ID);
        ohmEthPriceFeed.setAnsweredInRound(PRICE_FEED_ROUND_ID);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceMul(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, ohmDaiPrice);
    }

    function test_getTwoFeedPriceMul_revertsOnNumeratorRoundIdMismatchFuzz(uint80 roundId_) public {
        uint80 roundId = uint80(bound(roundId_, 0, type(uint80).max));
        vm.assume(roundId != PRICE_FEED_ROUND_ID);

        // Mock answeredInRound > roundId
        ohmEthPriceFeed.setRoundId(roundId);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedRoundMismatch.selector,
            address(ohmEthPriceFeed),
            roundId,
            PRICE_FEED_ROUND_ID
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_denominatorRoundIdValid() public {
        // Mock answeredInRound = roundId
        ethDaiPriceFeed.setRoundId(PRICE_FEED_ROUND_ID);
        ethDaiPriceFeed.setAnsweredInRound(PRICE_FEED_ROUND_ID);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceMul(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, ohmDaiPrice);
    }

    function test_getTwoFeedPriceMul_revertsOnDenominatorRoundIdMismatchFuzz(
        uint80 roundId_
    ) public {
        uint80 roundId = uint80(bound(roundId_, 0, type(uint80).max));
        vm.assume(roundId != PRICE_FEED_ROUND_ID);

        // Mock answeredInRound > roundId
        ethDaiPriceFeed.setRoundId(roundId);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedRoundMismatch.selector,
            address(ethDaiPriceFeed),
            roundId,
            PRICE_FEED_ROUND_ID
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_priceDecimalsFuzz(uint8 priceDecimals_) public {
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceMul(address(0), priceDecimals, params);

        assertEq(priceInt, 10 * 10 ** priceDecimals); // Expected price is 10, adjusted with decimals
    }

    function test_getTwoFeedPriceMul_priceFeedDecimalsFuzz(
        uint8 priceFeedOneDecimals_,
        uint8 priceFeedTwoDecimals_
    ) public {
        uint8 priceFeedOneDecimals = uint8(
            bound(priceFeedOneDecimals_, MIN_DECIMALS, MAX_DECIMALS)
        );
        uint8 priceFeedTwoDecimals = uint8(
            bound(priceFeedTwoDecimals_, MIN_DECIMALS, MAX_DECIMALS)
        );

        ohmEthPriceFeed.setLatestAnswer(
            int256(ohmEthPrice.mulDiv(10 ** priceFeedOneDecimals, 10 ** PRICE_DECIMALS))
        );
        ohmEthPriceFeed.setDecimals(priceFeedOneDecimals);
        ethDaiPriceFeed.setLatestAnswer(
            int256(ethDaiPrice.mulDiv(10 ** priceFeedTwoDecimals, 10 ** PRICE_DECIMALS))
        );
        ethDaiPriceFeed.setDecimals(priceFeedTwoDecimals);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceMul(
            address(0),
            PRICE_DECIMALS,
            params
        );

        assertEq(priceInt, 10 * 10 ** PRICE_DECIMALS); // Expected price is 10, adjusted with decimals
    }

    function test_getTwoFeedPriceMul_fuzz(
        uint8 priceFeedOneDecimals_,
        uint8 priceFeedTwoDecimals_,
        uint8 priceDecimals_
    ) public {
        uint8 priceFeedOneDecimals = uint8(
            bound(priceFeedOneDecimals_, MIN_DECIMALS, MAX_DECIMALS)
        );
        uint8 priceFeedTwoDecimals = uint8(
            bound(priceFeedTwoDecimals_, MIN_DECIMALS, MAX_DECIMALS)
        );
        uint8 priceDecimals = uint8(bound(priceDecimals_, MIN_DECIMALS, MAX_DECIMALS));

        ohmEthPriceFeed.setLatestAnswer(
            int256(ohmEthPrice.mulDiv(10 ** priceFeedOneDecimals, 10 ** PRICE_DECIMALS))
        );
        ohmEthPriceFeed.setDecimals(priceFeedOneDecimals);
        ethDaiPriceFeed.setLatestAnswer(
            int256(ethDaiPrice.mulDiv(10 ** priceFeedTwoDecimals, 10 ** PRICE_DECIMALS))
        );
        ethDaiPriceFeed.setDecimals(priceFeedTwoDecimals);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            ethDaiPriceFeed,
            UPDATE_THRESHOLD
        );
        uint256 priceInt = chainlinkSubmodule.getTwoFeedPriceMul(address(0), priceDecimals, params);

        assertEq(priceInt, 10 * 10 ** priceDecimals); // Expected price is 10, adjusted with decimals
    }

    function test_getTwoFeedPriceMul_revertsOnNumeratorDecimalsMaximum() public {
        ohmEthPriceFeed.setDecimals(255);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedDecimalsOutOfBounds.selector,
            address(ohmEthPriceFeed),
            255,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_revertsOnDenominatorDecimalsMaximum() public {
        daiEthPriceFeed.setDecimals(255);

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_FeedDecimalsOutOfBounds.selector,
            address(daiEthPriceFeed),
            255,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    function test_getTwoFeedPriceMul_revertsOnPriceDecimalsMaximum() public {
        uint8 priceDecimals = MAX_DECIMALS + 1;

        bytes memory err = abi.encodeWithSelector(
            ChainlinkPriceFeeds.Chainlink_OutputDecimalsOutOfBounds.selector,
            priceDecimals,
            MAX_DECIMALS
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            ohmEthPriceFeed,
            UPDATE_THRESHOLD,
            daiEthPriceFeed,
            UPDATE_THRESHOLD
        );
        chainlinkSubmodule.getTwoFeedPriceMul(address(0), priceDecimals, params);
    }
}
