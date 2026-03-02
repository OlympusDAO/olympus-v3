// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-variable,mixed-case-function)
pragma solidity >=0.8.0;

// Test
import {PythPriceFeedsTest} from "./PythPriceFeedsTest.sol";
import {MockPyth} from "src/test/mocks/MockPyth.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {PythPriceFeeds} from "src/modules/PRICE/submodules/feeds/PythPriceFeeds.sol";

contract PythPriceFeedsGetTwoFeedPriceMulTest is PythPriceFeedsTest {
    using FullMath for uint256;

    // =========  TWO FEED TESTS - MUL ========= //

    // ========= PARAMS LENGTH VALIDATION ========= //

    function test_revertsOnParamsEmpty() public {
        bytes memory err = abi.encodeWithSelector(PythPriceFeeds.Pyth_ParamsInvalid.selector, "");
        vm.expectRevert(err);

        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, "");
    }

    function test_revertsOnParamsTooShort() public {
        bytes memory shortParams = new bytes(255); // 1 byte short of 256
        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        for (uint256 i = 0; i < 255; i++) {
            shortParams[i] = params[i];
        }

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsInvalid.selector,
            shortParams
        );
        vm.expectRevert(err);

        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, shortParams);
    }

    function test_revertsOnParamsTooLong() public {
        bytes memory longParams = new bytes(512); // Double the expected size
        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        for (uint256 i = 0; i < 256; i++) {
            longParams[i] = params[i];
        }

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsInvalid.selector,
            longParams
        );
        vm.expectRevert(err);

        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, longParams);
    }

    // given all parameters are valid for two feeds
    //  [X] it returns the correct multiplied price (first * second) in output decimals
    function test_success() public view {
        // First feed: 1.23456789 (expo=-8) = 1234567890000000000 in 18 decimals
        // Second feed: 0.0000000005 (expo=-18) = 500000000 in 18 decimals
        // Result: (1234567890000000000 * 500000000) / 10^18
        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);

        // (1234567890000000000 * 500000000) / 10^18 = 617283945000
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(
            uint256(500000000),
            10 ** uint256(PRICE_DECIMALS)
        );
        assertEq(priceInt, expected, "Multiplied price should match expected calculation");
    }

    // given the first pyth contract address is zero
    //  [X] it reverts with Pyth_ParamsPythInvalid
    function test_firstPythZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsPythInvalid.selector,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(0),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the second pyth contract address is zero
    //  [X] it reverts with Pyth_ParamsPythInvalid
    function test_secondPythZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsPythInvalid.selector,
            4,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(0),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the first price feed ID is zero
    //  [X] it reverts with Pyth_ParamsPriceFeedIdInvalid
    function test_firstPriceFeedIdZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsPriceFeedIdInvalid.selector,
            1,
            bytes32(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            bytes32(0),
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the second price feed ID is zero
    //  [X] it reverts with Pyth_ParamsPriceFeedIdInvalid
    function test_secondPriceFeedIdZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsPriceFeedIdInvalid.selector,
            5,
            bytes32(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            bytes32(0),
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the first update threshold is zero
    //  [X] it reverts with Pyth_ParamsUpdateThresholdInvalid
    function test_firstUpdateThresholdZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsUpdateThresholdInvalid.selector,
            2,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            0,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the second update threshold is zero
    //  [X] it reverts with Pyth_ParamsUpdateThresholdInvalid
    function test_secondUpdateThresholdZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsUpdateThresholdInvalid.selector,
            6,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            0,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the first max confidence is zero
    //  [X] it reverts with Pyth_ParamsMaxConfidenceInvalid
    function test_firstMaxConfidenceZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsMaxConfidenceInvalid.selector,
            3,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            0,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the second max confidence is zero
    //  [X] it reverts with Pyth_ParamsMaxConfidenceInvalid
    function test_secondMaxConfidenceZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsMaxConfidenceInvalid.selector,
            7,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            0
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the first feed has invalid price (<= 0)
    //  [X] it reverts with Pyth_FeedPriceInvalid
    function test_firstFeedPriceInvalid_reverts(int64 price_) public {
        price_ = int64(bound(price_, type(int64).min, 0));
        pyth.setPrice(PRICE_ID_1, price_, CONF_1, EXPO_1, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedPriceInvalid.selector,
            address(pyth),
            PRICE_ID_1,
            price_
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the second feed has invalid price (<= 0)
    //  [X] it reverts with Pyth_FeedPriceInvalid
    function test_secondFeedPriceInvalid_reverts(int64 price_) public {
        price_ = int64(bound(price_, type(int64).min, 0));
        pyth.setPrice(PRICE_ID_3, price_, CONF_3, EXPO_3, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedPriceInvalid.selector,
            address(pyth),
            PRICE_ID_3,
            price_
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the first price feed is not found
    //  [X] it reverts with PriceFeedNotFound
    function test_givenFirstFeedPriceFeedNotFound_reverts() public {
        bytes memory err = abi.encodeWithSelector(MockPyth.PriceFeedNotFound.selector);
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000001),
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the second price feed is not found
    //  [X] it reverts with PriceFeedNotFound
    function test_givenSecondFeedPriceFeedNotFound_reverts() public {
        bytes memory err = abi.encodeWithSelector(MockPyth.PriceFeedNotFound.selector);
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000001),
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the first feed publish time is < the threshold boundary
    //  [X] it reverts with StalePrice
    function test_givenFirstFeedStalePrice_reverts(uint256 publishTime_) public {
        // Bound publish time to be stale (publishTime < block.timestamp - UPDATE_THRESHOLD)
        publishTime_ = bound(publishTime_, 1, block.timestamp - UPDATE_THRESHOLD - 1);
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, publishTime_);

        bytes memory err = abi.encodeWithSelector(MockPyth.StalePrice.selector);
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the second feed publish time is < the threshold boundary
    //  [X] it reverts with StalePrice
    function test_givenSecondFeedStalePrice_reverts(uint256 publishTime_) public {
        // Bound publish time to be stale (publishTime < block.timestamp - UPDATE_THRESHOLD)
        publishTime_ = bound(publishTime_, 1, block.timestamp - UPDATE_THRESHOLD - 1);
        pyth.setPrice(PRICE_ID_3, PRICE_3, CONF_3, EXPO_3, publishTime_);

        bytes memory err = abi.encodeWithSelector(MockPyth.StalePrice.selector);
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the first feed expo is negative (expo = -8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_givenFirstFeedExpoNegative_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = -8, outputDecimals = 18
        // confidenceExponent = 18 + (-8) = 10
        // maxConfidenceInPythScale = maxConfidence / 10^10 = 2e16 / 1e10 = 2e6
        priceConfidence_ = uint64(bound(priceConfidence_, 2e6 + 1, type(uint64).max));
        pyth.setPrice(PRICE_ID_1, PRICE_1, priceConfidence_, EXPO_1, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedConfidenceExcessive.selector,
            address(pyth),
            PRICE_ID_1,
            priceConfidence_,
            uint64(2e6)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_givenFirstFeedExpoNegative() public view {
        // First feed: expo = -8, price = 123456789 -> 1.23456789 in 18 decimals = 1234567890000000000
        // Second feed: expo = -18, price = 500000000 -> 500000000 in 18 decimals
        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);

        // (1234567890000000000 * 500000000) / 10^18 = 617283945000
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(500000000, 10 ** PRICE_DECIMALS);
        assertEq(priceInt, expected, "Price should match expected for negative expo first feed");
    }

    // given the first feed expo is positive (expo > 0)
    //  [X] it reverts with Pyth_ExponentPositive
    function test_givenFirstFeedExpoPositive_reverts(int32 expo_) public {
        // Bound expo to be positive (> 0) to test Pyth_ExponentPositive error
        // Keep expo within reasonable range [1, 32] to avoid overflow in calculations
        expo_ = int32(bound(int256(expo_), 1, 32));
        int64 price = 100;
        pyth.setPrice(PRICE_ID_1, price, CONF_1, expo_, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ExponentPositive.selector,
            address(pyth),
            PRICE_ID_1,
            expo_
        );
        vm.expectRevert(err);

        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the first feed expo is zero (expo = 0, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_givenFirstFeedExpoZero_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = 0, outputDecimals = 18
        // confidenceExponent = 18 + 0 = 18
        // Use a higher maxConfidence to get a meaningful threshold
        // maxConfidence = 1e19 -> maxConfidenceInPythScale = 1e19 / 1e18 = 10
        uint256 maxConfidence = 1e19;
        uint64 maxConfInPythScale = 10;
        priceConfidence_ = uint64(
            bound(priceConfidence_, maxConfInPythScale + 1, type(uint64).max)
        );
        int32 expo = 0;
        pyth.setPrice(PRICE_ID_1, PRICE_1, priceConfidence_, expo, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedConfidenceExcessive.selector,
            address(pyth),
            PRICE_ID_1,
            priceConfidence_,
            maxConfInPythScale
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            maxConfidence,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_givenFirstFeedExpoZero() public {
        // First feed: expo = 0, price = 100 -> 100 * 10^18
        int64 price = 100;
        int32 expo = 0;
        pyth.setPrice(PRICE_ID_1, price, 1, expo, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            type(uint64).max, // Ensures confidence interval is below the maximum
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);

        // First: 100 * 10^18, Second: 500000000 (18 dec)
        // Result: (100 * 10^18 * 500000000) / 10^18 = 5 * 10^10
        uint256 firstPrice = uint256(100) * 10 ** 18;
        uint256 expected = firstPrice.mulDiv(500000000, 10 ** PRICE_DECIMALS);
        assertEq(priceInt, expected, "Price should match expected for zero expo first feed");
    }

    // given the first feed expo equals negative outputDecimals (expo = -18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_givenFirstFeedExpoNegativeEqualsOutputDecimals_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = -18, outputDecimals = 18
        // confidenceExponent = 18 + (-18) = 0
        // maxConfidenceInPythScale = maxConfidence / 10^0 = 2e16
        priceConfidence_ = uint64(bound(priceConfidence_, 2e16 + 1, type(uint64).max));
        int32 expo = -18;
        pyth.setPrice(PRICE_ID_1, PRICE_1, priceConfidence_, expo, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedConfidenceExcessive.selector,
            address(pyth),
            PRICE_ID_1,
            priceConfidence_,
            uint64(2e16)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_givenFirstFeedExpoNegativeEqualsOutputDecimals() public {
        // First feed: expo = -18, price = 1e9 -> 1e9 (no scaling)
        int64 price = 1e9;
        int32 expo = -18;
        pyth.setPrice(PRICE_ID_1, price, CONF_1, expo, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);

        // First: 1e9, Second: 500000000 (18 dec)
        // Result: (1e9 * 500000000) / 10^18 = 5e17 / 1e18 = 0 (rounds down)
        uint256 firstPrice = uint256(1e9);
        uint256 expected = firstPrice.mulDiv(500000000, 10 ** PRICE_DECIMALS);
        assertEq(
            priceInt,
            expected,
            "Price should match expected when first feed expo equals negative outputDecimals"
        );
    }

    // given the first feed expo is very negative (expo = -20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_givenFirstFeedExpoVeryNegative_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = -20, outputDecimals = 18
        // confidenceExponent = 18 + (-20) = -2
        // maxConfidenceInPythScale = maxConfidence * 10^2 = 2e16 * 100 = 2e18
        priceConfidence_ = uint64(bound(priceConfidence_, 2e18 + 1, type(uint64).max));
        int32 expo = -20;
        pyth.setPrice(PRICE_ID_1, PRICE_1, priceConfidence_, expo, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedConfidenceExcessive.selector,
            address(pyth),
            PRICE_ID_1,
            priceConfidence_,
            uint64(2e18)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price by dividing
    function test_givenFirstFeedExpoVeryNegative() public {
        // First feed: expo = -20, price = 1e10 -> 1e10 / 10^2 = 1e8
        int64 price = 1e10;
        int32 expo = -20;
        pyth.setPrice(PRICE_ID_1, price, CONF_1, expo, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);

        // First: 1e10 / 100 = 1e8, Second: 500000000 (18 dec)
        // Result: (1e8 * 500000000) / 10^18 = 5e16 / 1e18 = 0 (rounds down)
        uint256 firstPrice = uint256(1e10) / 100;
        uint256 expected = firstPrice.mulDiv(500000000, 10 ** PRICE_DECIMALS);
        assertEq(
            priceInt,
            expected,
            "Price should match expected for very negative expo first feed"
        );
    }

    // given the first feed publish time is >= the threshold boundary
    //  [X] it returns the correct price
    function test_givenFirstFeedPublishTimeAboveThreshold(uint256 publishTime_) public {
        // Bound the publish time to a reasonable value
        publishTime_ = bound(publishTime_, block.timestamp - UPDATE_THRESHOLD, block.timestamp);
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, publishTime_);
        // Second feed keeps publish time as set in setUp()

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);

        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(500000000, 10 ** PRICE_DECIMALS);
        assertEq(
            priceInt,
            expected,
            "Multiplied price should match expected when first feed at threshold"
        );
    }

    // given the second feed expo is negative (expo = -8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_givenSecondFeedExpoNegative_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = -8, outputDecimals = 18
        // confidenceExponent = 18 + (-8) = 10
        // maxConfidenceInPythScale = maxConfidence / 10^10 = 2e16 / 1e10 = 2e6
        priceConfidence_ = uint64(bound(priceConfidence_, 2e6 + 1, type(uint64).max));
        pyth.setPrice(PRICE_ID_3, PRICE_3, priceConfidence_, EXPO_1, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedConfidenceExcessive.selector,
            address(pyth),
            PRICE_ID_3,
            priceConfidence_,
            uint64(2e6)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_givenSecondFeedExpoNegative() public {
        // Second feed: expo = -8, price = 123456789 -> 1.23456789 in 18 decimals = 1234567890000000000
        pyth.setPrice(PRICE_ID_3, PRICE_1, CONF_1, EXPO_1, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);

        // First: 1234567890000000000 (18 dec), Second: 1234567890000000000
        // Result: (1234567890000000000 * 1234567890000000000) / 10^18
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(
            EXPECTED_PRICE_1_18_DEC,
            10 ** PRICE_DECIMALS
        );
        assertEq(priceInt, expected, "Price should match expected for negative expo second feed");
    }

    // given the second feed expo is positive (expo > 0)
    //  [X] it reverts with Pyth_ExponentPositive
    function test_givenSecondFeedExpoPositive_reverts(int32 expo_) public {
        // Bound expo to be positive (> 0) to test Pyth_ExponentPositive error
        // Keep expo within reasonable range [1, 32] to avoid overflow in calculations
        expo_ = int32(bound(int256(expo_), 1, 32));
        int64 price = 100;
        pyth.setPrice(PRICE_ID_3, price, CONF_1, expo_, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ExponentPositive.selector,
            address(pyth),
            PRICE_ID_3,
            expo_
        );
        vm.expectRevert(err);

        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    // given the second feed expo is zero (expo = 0, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_givenSecondFeedExpoZero_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = 0, outputDecimals = 18
        // confidenceExponent = 18 + 0 = 18
        // Use a higher maxConfidence to get a meaningful threshold
        // maxConfidence = 1e19 -> maxConfidenceInPythScale = 1e19 / 1e18 = 10
        uint256 maxConfidence = 1e19;
        uint64 maxConfInPythScale = 10;
        priceConfidence_ = uint64(
            bound(priceConfidence_, maxConfInPythScale + 1, type(uint64).max)
        );
        int32 expo = 0;
        pyth.setPrice(PRICE_ID_3, PRICE_3, priceConfidence_, expo, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedConfidenceExcessive.selector,
            address(pyth),
            PRICE_ID_3,
            priceConfidence_,
            maxConfInPythScale
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            maxConfidence
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_givenSecondFeedExpoZero() public {
        // Second feed: expo = 0, price = 100 -> 100 * 10^18
        int64 price = 100;
        int32 expo = 0;
        pyth.setPrice(PRICE_ID_3, price, 1, expo, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            type(uint64).max // Ensures confidence interval is below the maximum
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);

        // First: 1234567890000000000 (18 dec), Second: 100 * 10^18
        // Result: (1234567890000000000 * 100 * 10^18) / 10^18 = 1234567890000000000 * 100
        uint256 secondPrice = uint256(100) * 10 ** 18;
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(secondPrice, 10 ** PRICE_DECIMALS);
        assertEq(priceInt, expected, "Price should match expected for zero expo second feed");
    }

    // given the second feed expo equals negative outputDecimals (expo = -18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_givenSecondFeedExpoNegativeEqualsOutputDecimals_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = -18, outputDecimals = 18
        // confidenceExponent = 18 + (-18) = 0
        // maxConfidenceInPythScale = maxConfidence / 10^0 = 2e16
        priceConfidence_ = uint64(bound(priceConfidence_, 2e16 + 1, type(uint64).max));
        int32 expo = -18;
        pyth.setPrice(PRICE_ID_3, PRICE_3, priceConfidence_, expo, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedConfidenceExcessive.selector,
            address(pyth),
            PRICE_ID_3,
            priceConfidence_,
            uint64(2e16)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_givenSecondFeedExpoNegativeEqualsOutputDecimals() public {
        // Second feed: expo = -18, price = 1e9 -> 1e9 (no scaling)
        int64 price = 1e9;
        int32 expo = -18;
        pyth.setPrice(PRICE_ID_3, price, CONF_1, expo, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);

        // First: 1234567890000000000 (18 dec), Second: 1e9
        // Result: (1234567890000000000 * 1e9) / 10^18 = 1234567890
        uint256 secondPrice = uint256(1e9);
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(secondPrice, 10 ** PRICE_DECIMALS);
        assertEq(
            priceInt,
            expected,
            "Price should match expected when second feed expo equals negative outputDecimals"
        );
    }

    // given the second feed expo is very negative (expo = -20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_givenSecondFeedExpoVeryNegative_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = -20, outputDecimals = 18
        // confidenceExponent = 18 + (-20) = -2
        // maxConfidenceInPythScale = maxConfidence * 10^2 = 2e16 * 100 = 2e18
        priceConfidence_ = uint64(bound(priceConfidence_, 2e18 + 1, type(uint64).max));
        int32 expo = -20;
        pyth.setPrice(PRICE_ID_3, PRICE_3, priceConfidence_, expo, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedConfidenceExcessive.selector,
            address(pyth),
            PRICE_ID_3,
            priceConfidence_,
            uint64(2e18)
        );
        vm.expectRevert(err);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price by dividing
    function test_givenSecondFeedExpoVeryNegative() public {
        // Second feed: expo = -20, price = 1e10 -> 1e10 / 10^2 = 1e8
        int64 price = 1e10;
        int32 expo = -20;
        pyth.setPrice(PRICE_ID_3, price, CONF_1, expo, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);

        // First: 1234567890000000000 (18 dec), Second: 1e8
        // Result: (1234567890000000000 * 1e8) / 10^18 = 123456789
        uint256 secondPrice = uint256(1e10) / 100;
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(secondPrice, 10 ** PRICE_DECIMALS);
        assertEq(
            priceInt,
            expected,
            "Price should match expected for very negative expo second feed"
        );
    }

    // given the second feed publish time is >= the threshold boundary
    //  [X] it returns the correct price
    function test_givenSecondFeedPublishTimeAboveThreshold(uint256 publishTime_) public {
        // Bound the publish time to a reasonable value
        publishTime_ = bound(publishTime_, block.timestamp - UPDATE_THRESHOLD, block.timestamp);
        pyth.setPrice(PRICE_ID_3, PRICE_3, CONF_3, EXPO_3, publishTime_);
        // First feed keeps publish time as set in setUp()

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), PRICE_DECIMALS, params);

        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(500000000, 10 ** PRICE_DECIMALS);
        assertEq(
            priceInt,
            expected,
            "Multiplied price should match expected when second feed at threshold"
        );
    }

    // given outputDecimals is different from default (18)
    //  [X] it correctly converts prices to the specified output decimals
    function test_outputDecimalsFuzz(uint8 outputDecimals_) public {
        // Bound output decimals to reasonable range [18, 36] to avoid overflow
        outputDecimals_ = uint8(bound(outputDecimals_, 18, 36));
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp);
        pyth.setPrice(PRICE_ID_3, PRICE_3, CONF_3, EXPO_3, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals_) / 10 ** 18, // scale max confidence to the new output decimals
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals_) / 10 ** 18 // scale max confidence to the new output decimals
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), outputDecimals_, params);

        // First: price = 123456789, expo = -8 -> converts to 123456789 * 10^(outputDecimals_ - 8)
        /// forge-lint: disable-next-line(unsafe-typecast)
        uint256 firstPrice = uint256(uint64(PRICE_1)) * 10 ** (outputDecimals_ - 8);
        // Second: price = 500000000, expo = -18 -> converts to 500000000 * 10^(outputDecimals_ - 18)
        /// forge-lint: disable-next-line(unsafe-typecast)
        uint256 secondPrice = uint256(uint64(PRICE_3)) * 10 ** (outputDecimals_ - 18);
        uint256 expected = firstPrice.mulDiv(secondPrice, 10 ** outputDecimals_);
        assertEq(priceInt, expected, "Price should match expected for fuzzed output decimals");
    }

    // given outputDecimals is < the expo of price feed one
    //  given that price one is < 1
    //   [X] the price loses precision
    function test_outputDecimalsLessThanPriceOneExpo_priceLessThanOne() public {
        // Bound output decimals to 9, which is less than the expo (18) of price feed one
        uint8 outputDecimals = 9;
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp);
        // This price will lose precision when converted to output decimals
        // The price is also < 1 in 18 decimal scale
        pyth.setPrice(PRICE_ID_3, 122222222222222222, CONF_3, EXPO_3, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18, // scale max confidence to the new output decimals
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18 // scale max confidence to the new output decimals
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), outputDecimals, params);

        // First price:
        // expo = -18, price = 122222222222222222
        // outputDecimals = 9, price = 122222222.222222222
        // Second price:
        // expo = -8, price = 123456789 (1.23456789 * 10^8)
        // outputDecimals = 9, price = 1234567890 (1.23456789 * 10^9)
        // Expected result: 122222222 * 1234567890 / 10^9 = 150891630
        uint256 expected = 150891630;
        assertEq(priceInt, expected, "Price should lose precision");
    }

    //  given that price one rounds down to 0
    //   [X] it returns zero
    function test_outputDecimalsLessThanPriceOneExpo_priceRoundsDownToZero() public {
        // Bound output decimals to 9, which is less than the expo (18) of price feed one
        uint8 outputDecimals = 9;
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp);
        // This will round down to 0 when converted to output decimals
        pyth.setPrice(PRICE_ID_3, 122222222, CONF_3, EXPO_3, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18, // scale max confidence to the new output decimals
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18 // scale max confidence to the new output decimals
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), outputDecimals, params);

        // First price:
        // expo = -18, price = 122222222
        // outputDecimals = 9, price = 0 (122222222 * 10^9 / 10^18 is less than 1)
        // Expected result: 0
        uint256 expected = 0;
        assertEq(priceInt, expected, "Price should round down to zero");
    }

    //  [X] the price loses precision
    function test_outputDecimalsLessThanPriceOneExpo() public {
        // Bound output decimals to 9, which is less than the expo (18) of price feed one
        uint8 outputDecimals = 9;
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp);
        // This price will lose precision when converted to output decimals
        pyth.setPrice(PRICE_ID_3, 1222222222222222222, CONF_3, EXPO_3, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18, // scale max confidence to the new output decimals
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18 // scale max confidence to the new output decimals
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), outputDecimals, params);

        // First price:
        // expo = -18, price = 1222222222222222222
        // outputDecimals = 9, price = 1222222222.222222222
        // Second price:
        // expo = -8, price = 123456789 (1.23456789 * 10^8)
        // outputDecimals = 9, price = 1234567890 (1.23456789 * 10^9)
        // Expected result: 1222222222 * 1234567890 / 10^9 = 1508916309
        uint256 expected = 1508916309;
        assertEq(priceInt, expected, "Price should lose precision");
    }

    // given outputDecimals is < the expo of price feed two
    //  given that price two is < 1
    //   [X] the price loses precision
    function test_outputDecimalsLessThanPriceTwoExpo_priceLessThanOne() public {
        // Bound output decimals to 9, which is less than the expo (18) of price feed two
        uint8 outputDecimals = 9;
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp);
        // This price will lose precision when converted to output decimals
        // The price is also < 1 in 18 decimal scale
        pyth.setPrice(PRICE_ID_3, 122222222222222222, CONF_3, EXPO_3, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18, // scale max confidence to the new output decimals
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18 // scale max confidence to the new output decimals
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), outputDecimals, params);

        // First price:
        // expo = -8, price = 123456789 (1.23456789 * 10^8)
        // outputDecimals = 9, price = 1234567890 (1.23456789 * 10^9)
        // Second price:
        // expo = -18, price = 122222222222222222
        // outputDecimals = 9, price = 122222222.222222222
        // Expected result: 1234567890 * 122222222 / 10^9 = 150891630
        uint256 expected = 150891630;
        assertEq(priceInt, expected, "Price should lose precision");
    }

    //  given that price two rounds down to 0
    //   [X] it returns zero
    function test_outputDecimalsLessThanPriceTwoExpo_priceRoundsDownToZero() public {
        // Bound output decimals to 9, which is less than the expo (18) of price feed two
        uint8 outputDecimals = 9;
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp);
        // This will round down to 0 when converted to output decimals
        pyth.setPrice(PRICE_ID_3, 122222222, CONF_3, EXPO_3, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18, // scale max confidence to the new output decimals
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18 // scale max confidence to the new output decimals
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), outputDecimals, params);

        // First price:
        // expo = -8, price = 123456789 (1.23456789 * 10^8)
        // outputDecimals = 9, price = 1234567890 (1.23456789 * 10^9)
        // Second price:
        // expo = -18, price = 122222222
        // outputDecimals = 9, price = 0 (122222222 * 10^9 / 10^18 is less than 1)
        // Expected result: 0
        uint256 expected = 0;
        assertEq(priceInt, expected, "Price should round down to zero");
    }

    //  [X] the price loses precision
    function test_outputDecimalsLessThanPriceTwoExpo() public {
        // Bound output decimals to 9, which is less than the expo (18) of price feed two
        uint8 outputDecimals = 9;
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp);
        // This price will lose precision when converted to output decimals
        pyth.setPrice(PRICE_ID_3, 1222222222222222222, CONF_3, EXPO_3, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18, // scale max confidence to the new output decimals
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18 // scale max confidence to the new output decimals
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceMul(address(0), outputDecimals, params);

        // First price:
        // expo = -8, price = 123456789 (1.23456789 * 10^8)
        // outputDecimals = 9, price = 1234567890 (1.23456789 * 10^9)
        // Second price:
        // expo = -18, price = 1222222222222222222
        // outputDecimals = 9, price = 1222222222.222222222
        // Expected result: 1234567890 * 1222222222 / 10^9 = 1508916309
        uint256 expected = 1508916309;
        assertEq(priceInt, expected, "Price should lose precision");
    }
}
/// forge-lint: disable-end(mixed-case-variable,mixed-case-function)
