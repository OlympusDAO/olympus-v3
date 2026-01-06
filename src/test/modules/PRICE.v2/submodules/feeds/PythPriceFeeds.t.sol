// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-variable,mixed-case-function)
pragma solidity >=0.8.0;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";

// Mocks
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {MockPyth} from "src/test/mocks/MockPyth.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";

// Bophades
import {Kernel} from "src/Kernel.sol";
import {PythPriceFeeds} from "src/modules/PRICE/submodules/feeds/PythPriceFeeds.sol";

contract PythPriceFeedsTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for PythPriceFeeds;

    MockPyth internal pyth;
    MockPyth internal secondPyth;

    Kernel internal kernel;
    MockPrice internal mockPrice;
    PythPriceFeeds internal pythSubmodule;

    bytes32 internal constant PRICE_ID_1 = keccak256("PRICE_ID_1");
    bytes32 internal constant PRICE_ID_2 = keccak256("PRICE_ID_2");
    bytes32 internal constant PRICE_ID_3 = keccak256("PRICE_ID_3");

    // Example: price=123456789, expo=-8 represents 1.23456789
    int64 internal constant PRICE_1 = 123456789;
    int32 internal constant EXPO_1 = -8;
    uint64 internal constant CONF_1 = 1000000;
    uint256 internal constant EXPECTED_PRICE_1_18_DEC = 1234567890000000000; // 1.23456789 * 10^18

    // Example: price=100000000, expo=8 represents 100000000 * 10^8
    int64 internal constant PRICE_2 = 100000000;
    int32 internal constant EXPO_2 = 8;
    uint64 internal constant CONF_2 = 2000000;

    // Example: price=500000000, expo=-18 represents 0.0000000005
    int64 internal constant PRICE_3 = 500000000;
    int32 internal constant EXPO_3 = -18;
    uint64 internal constant CONF_3 = 500000;

    uint8 internal constant PRICE_DECIMALS = 18;
    uint48 internal constant UPDATE_THRESHOLD = 100;
    // MAX_CONFIDENCE is in output decimals (18 decimals)
    // CONF_1 = 1000000 with expo=-8
    // In decimal: 1000000 * 10^-8 = 0.01
    // In output decimals (18): 0.01 * 10^18 = 10000000000000000 (1e16)
    // Set MAX_CONFIDENCE to 2e16 to allow CONF_1 but reject higher values
    uint64 internal constant MAX_CONFIDENCE = 20000000000000000; // 2 * 10^16 in 18 decimals

    uint8 internal constant BASE_10_MAX_EXPONENT = 50;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021

        // Set up the Pyth submodule
        {
            // Deploy kernel
            kernel = new Kernel();

            // Deploy mockPrice
            mockPrice = new MockPrice(kernel, uint8(18), uint32(8 hours));
            mockPrice.setTimestamp(uint48(block.timestamp));
            mockPrice.setPriceDecimals(PRICE_DECIMALS);

            // Deploy Pyth submodule
            pythSubmodule = new PythPriceFeeds(mockPrice);
        }

        // Set up the Pyth contracts
        {
            pyth = new MockPyth();
            secondPyth = new MockPyth();

            // With the default update threshold, these prices will NOT be stale

            // Set up price feed 1: 1.23456789 (expo=-8)
            pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp - UPDATE_THRESHOLD);

            // Set up price feed 2: 100000000 * 10^8 (expo=8)
            pyth.setPrice(PRICE_ID_2, PRICE_2, CONF_2, EXPO_2, block.timestamp - UPDATE_THRESHOLD);

            // Set up price feed 3: 0.0000000005 (expo=-18)
            pyth.setPrice(PRICE_ID_3, PRICE_3, CONF_3, EXPO_3, block.timestamp - UPDATE_THRESHOLD);
        }
    }

    // =========  HELPER METHODS ========= //

    function encodeOneFeedParams(
        address pyth_,
        bytes32 priceFeedId,
        uint48 updateThreshold,
        uint64 maxConfidence
    ) internal pure returns (bytes memory params) {
        return abi.encode(pyth_, priceFeedId, updateThreshold, maxConfidence);
    }

    function encodeTwoFeedParams(
        address firstPyth,
        bytes32 firstPriceFeedId,
        uint48 firstUpdateThreshold,
        uint64 firstMaxConfidence,
        address secondPyth,
        bytes32 secondPriceFeedId,
        uint48 secondUpdateThreshold,
        uint64 secondMaxConfidence
    ) internal pure returns (bytes memory params) {
        return
            abi.encode(
                firstPyth,
                firstPriceFeedId,
                firstUpdateThreshold,
                firstMaxConfidence,
                secondPyth,
                secondPriceFeedId,
                secondUpdateThreshold,
                secondMaxConfidence
            );
    }

    // =========  ONE FEED TESTS ========= //

    // given all parameters are valid
    //  [X] it returns the correct price in output decimals
    function test_getOneFeedPrice_success() public view {
        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        assertEq(
            priceInt,
            EXPECTED_PRICE_1_18_DEC,
            "Price should match expected value for expo=-8"
        );
    }

    // given the pyth contract address is zero
    //  [X] it reverts with Pyth_ParamsPythInvalid
    function test_getOneFeedPrice_revertsOnParamsFeedInvalid() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsPythInvalid.selector,
            0,
            address(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(
            address(0),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // given the price feed ID is zero
    //  [X] it reverts with Pyth_ParamsPriceFeedIdInvalid
    function test_getOneFeedPrice_revertsOnParamsPriceFeedIdInvalid() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsPriceFeedIdInvalid.selector,
            1,
            bytes32(0)
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            bytes32(0),
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // given the update threshold is zero
    //  [X] it reverts with Pyth_ParamsUpdateThresholdInvalid
    function test_getOneFeedPrice_revertsOnParamsUpdateThresholdInvalid() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsUpdateThresholdInvalid.selector,
            2,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(address(pyth), PRICE_ID_1, 0, MAX_CONFIDENCE);
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // given the max confidence is zero
    //  [X] it reverts with Pyth_ParamsMaxConfidenceInvalid
    function test_getOneFeedPrice_revertsOnParamsMaxConfidenceInvalid() public {
        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ParamsMaxConfidenceInvalid.selector,
            3,
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(address(pyth), PRICE_ID_1, UPDATE_THRESHOLD, 0);
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // given expo + outputDecimals > BASE_10_MAX_EXPONENT
    //  [X] it reverts with Pyth_ExponentOutOfBounds
    function test_getOneFeedPrice_revertsOnExponentOutOfBounds() public {
        // Set expo such that expo + outputDecimals > BASE_10_MAX_EXPONENT
        int32 largeExpo = 45; // 45 + 18 = 63 > 50
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, largeExpo, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ExponentOutOfBounds.selector,
            address(pyth),
            PRICE_ID_1,
            largeExpo,
            PRICE_DECIMALS,
            BASE_10_MAX_EXPONENT
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // given the pyth contract doesn't implement IPyth
    //  [X] it reverts with Pyth_FeedInvalid
    function test_getOneFeedPrice_revertsOnFeedInvalid() public {
        // Use a contract that doesn't implement IPyth
        address invalidPyth = address(0x1234);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedInvalid.selector,
            invalidPyth,
            PRICE_ID_1
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(
            invalidPyth,
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // given the price is zero
    //  [X] it reverts with Pyth_FeedPriceInvalid
    function test_getOneFeedPrice_revertsOnFeedPriceInvalid() public {
        // Set price to zero
        pyth.setPrice(PRICE_ID_1, 0, CONF_1, EXPO_1, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedPriceInvalid.selector,
            address(pyth),
            0
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // given the price is negative
    //  [X] it reverts with Pyth_FeedPriceInvalid
    function test_getOneFeedPrice_revertsOnFeedPriceInvalid_negative() public {
        // Set price to negative
        pyth.setPrice(PRICE_ID_1, -100, CONF_1, EXPO_1, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedPriceInvalid.selector,
            address(pyth),
            PRICE_ID_1,
            -100
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // given the publish time is before the update threshold
    //  [X] it reverts with StalePrice
    function test_getOneFeedPrice_givenStalePrice_reverts(uint256 publishTime_) public {
        // Bound publish time to be stale (publishTime < block.timestamp - UPDATE_THRESHOLD)
        publishTime_ = bound(publishTime_, 0, block.timestamp - UPDATE_THRESHOLD - 1);
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, publishTime_);

        bytes memory err = abi.encodeWithSelector(MockPyth.StalePrice.selector);
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // given expo is negative (expo = -8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getOneFeedPrice_maxConfidenceExceeded_reverts(uint64 priceConfidence_) public {
        // MAX_CONFIDENCE = 2e16 in output decimals (18)
        // CONF_1 = 1000000 with expo=-8 converts to 1e16 in output decimals, so it should pass
        // To exceed MAX_CONFIDENCE (2e16), we need conf * 10^10 > 2e16, so conf > 2e6
        priceConfidence_ = uint64(bound(priceConfidence_, 2e6 + 1, type(uint64).max));

        // Set the price data
        pyth.setPrice(PRICE_ID_1, PRICE_1, priceConfidence_, EXPO_1, block.timestamp);

        // Calculate the expected maxConfidence in Pyth scale
        // EXPO_1 = -8, PRICE_DECIMALS = 18
        // maxConfidence = 2e16 * 1 / 10^*(-8+18) = 2e16 * 1 / 10^10 = 2e6
        uint64 maxConfInPythScale = 2e6;

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedConfidenceExcessive.selector,
            address(pyth),
            PRICE_ID_1,
            priceConfidence_,
            maxConfInPythScale
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_getOneFeedPrice_givenExpoNegative() public view {
        // expo = -8, outputDecimals = 18, totalExponent = 10
        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        // price = 123456789, expo = -8, outputDecimals = 18
        // outputPrice = 123456789 * 10^(10) = 1234567890000000000
        assertEq(
            priceInt,
            EXPECTED_PRICE_1_18_DEC,
            "Price should match expected value for negative expo"
        );
    }

    // given expo is positive (expo = 8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [X] it correctly converts the price
    function test_getOneFeedPrice_success_expoPositive() public view {
        // expo = 8, outputDecimals = 18, totalExponent = 26
        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_2,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        // price = 100000000, expo = 8, outputDecimals = 18
        // outputPrice = 100000000 * 10^26
        assertEq(
            priceInt,
            100000000 * 10 ** 26,
            "Price should match expected value for positive expo"
        );
    }

    // given expo is zero (expo = 0, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [X] it correctly converts the price
    function test_getOneFeedPrice_success_expoZero() public {
        // expo = 0, outputDecimals = 18, totalExponent = 18
        int64 price = 123456789;
        int32 expo = 0;
        pyth.setPrice(PRICE_ID_1, price, CONF_1, expo, block.timestamp);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        // outputPrice = 123456789 * 10^18
        assertEq(priceInt, 123456789 * 10 ** 18, "Price should match expected value for zero expo");
    }

    // given expo equals positive outputDecimals (expo = 18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given expo equals negative outputDecimals (expo = -18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [X] it returns the price without scaling
    function test_getOneFeedPrice_success_expoEqualsNegativeOutputDecimals() public {
        // expo = -18, outputDecimals = 18, totalExponent = 0
        int64 price = 123456789;
        int32 expo = -18;
        pyth.setPrice(PRICE_ID_1, price, CONF_1, expo, block.timestamp);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        // outputPrice = 123456789 (no scaling needed)
        assertEq(
            priceInt,
            uint256(uint64(price)),
            "Price should match input value when expo equals negative outputDecimals"
        );
    }

    // given expo is very negative (expo = -20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [X] it correctly converts the price by dividing
    function test_getOneFeedPrice_success_expoVeryNegative() public {
        // expo = -20, outputDecimals = 18, totalExponent = -2
        int64 price = 100000000;
        int32 expo = -20;
        pyth.setPrice(PRICE_ID_1, price, CONF_1, expo, block.timestamp);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        // outputPrice = 100000000 / 10^2 = 1000000
        assertEq(priceInt, 1000000, "Price should match expected value for very negative expo");
    }

    // given expo is very positive (expo = 20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [X] it correctly converts the price by multiplying
    function test_getOneFeedPrice_success_expoVeryPositive() public {
        // expo = 20, outputDecimals = 18, totalExponent = 38
        int64 price = 100000000;
        int32 expo = 20;
        pyth.setPrice(PRICE_ID_1, price, CONF_1, expo, block.timestamp);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        // outputPrice = 100000000 * 10^38
        assertEq(
            priceInt,
            100000000 * 10 ** 38,
            "Price should match expected value for very positive expo"
        );
    }

    // TODO required?

    // given the confidence interval is below the maximum (after conversion)
    //  [X] it returns the correct price
    function test_getOneFeedPrice_success_confidenceEqualsMaximum() public {
        // Confidence interval equals maximum threshold
        // CONF_1 = 1000000 with expo=-8 converts to 1e16 in output decimals
        // MAX_CONFIDENCE = 2e16, so CONF_1 should pass
        // This test verifies that a confidence that is below the maximum passes
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        assertEq(
            priceInt,
            EXPECTED_PRICE_1_18_DEC,
            "Price should be valid when confidence is below maximum"
        );
    }

    // given the publish time is >= the threshold boundary
    //  [X] it returns the correct price
    function test_getOneFeedPrice_givenPublishTimeAboveThreshold(uint48 publishTime_) public {
        // Bound the publish time to a reasonable value
        publishTime_ = uint48(bound(publishTime_, block.timestamp - UPDATE_THRESHOLD, block.timestamp));
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, publishTime_);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        assertEq(
            priceInt,
            EXPECTED_PRICE_1_18_DEC,
            "Price should be valid when publish time is above threshold"
        );
    }

    // =========  TWO FEED TESTS - DIV ========= //

    // given all parameters are valid for two feeds
    //  [X] it returns the correct divided price (first / second) in output decimals
    function test_getTwoFeedPriceDiv_success() public view {
        // First feed: 1.23456789 (expo=-8) = 1234567890000000000 in 18 decimals
        // Second feed: 0.0000000005 (expo=-18) = 500000000 in 18 decimals
        // Result: 1234567890000000000 / 500000000 = 2469135780
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
        uint256 priceInt = pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);

        // (1234567890000000000 * 10^18) / 500000000 = 2469135780000000000000000000
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(10 ** PRICE_DECIMALS, 500000000);
        assertEq(priceInt, expected, "Divided price should match expected calculation");
    }

    // given the first pyth contract address is zero
    //  [X] it reverts with Pyth_ParamsPythInvalid
    function test_getTwoFeedPriceDiv_revertsOnParamsFirstFeedInvalid() public {
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the first price feed ID is zero
    //  [X] it reverts with Pyth_ParamsPriceFeedIdInvalid
    function test_getTwoFeedPriceDiv_revertsOnParamsFirstPriceIdInvalid() public {
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the first update threshold is zero
    //  [X] it reverts with Pyth_ParamsUpdateThresholdInvalid
    function test_getTwoFeedPriceDiv_revertsOnParamsFirstUpdateThresholdInvalid() public {
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the first max confidence is zero
    //  [X] it reverts with Pyth_ParamsMaxConfidenceInvalid
    function test_getTwoFeedPriceDiv_revertsOnParamsFirstMaxConfidenceInvalid() public {
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the second pyth contract address is zero
    //  [X] it reverts with Pyth_ParamsPythInvalid
    function test_getTwoFeedPriceDiv_revertsOnParamsSecondFeedInvalid() public {
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the second price feed ID is zero
    //  [X] it reverts with Pyth_ParamsPriceFeedIdInvalid
    function test_getTwoFeedPriceDiv_revertsOnParamsSecondPriceIdInvalid() public {
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the second update threshold is zero
    //  [X] it reverts with Pyth_ParamsUpdateThresholdInvalid
    function test_getTwoFeedPriceDiv_revertsOnParamsSecondUpdateThresholdInvalid() public {
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the second max confidence is zero
    //  [X] it reverts with Pyth_ParamsMaxConfidenceInvalid
    function test_getTwoFeedPriceDiv_revertsOnParamsSecondMaxConfidenceInvalid() public {
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the first feed has invalid price (<= 0)
    //  [X] it reverts with Pyth_FeedPriceInvalid
    function test_getTwoFeedPriceDiv_revertsOnFirstFeedInvalid() public {
        // First feed has invalid price
        pyth.setPrice(PRICE_ID_1, 0, CONF_1, EXPO_1, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedPriceInvalid.selector,
            address(pyth),
            PRICE_ID_1,
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
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the second feed has invalid price (<= 0)
    //  [X] it reverts with Pyth_FeedPriceInvalid
    function test_getTwoFeedPriceDiv_revertsOnSecondFeedInvalid() public {
        // Second feed has invalid price
        pyth.setPrice(PRICE_ID_3, 0, CONF_3, EXPO_3, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedPriceInvalid.selector,
            address(pyth),
            PRICE_ID_3,
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
            MAX_CONFIDENCE
        );
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the first feed publish time is < the threshold boundary
    //  [X] it reverts with StalePrice
    function test_getTwoFeedPriceDiv_givenFirstFeedStalePrice_reverts(uint256 publishTime_) public {
        // Bound publish time to be stale (publishTime < block.timestamp - UPDATE_THRESHOLD)
        publishTime_ = bound(publishTime_, 0, block.timestamp - UPDATE_THRESHOLD - 1);
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the second feed publish time is < the threshold boundary
    //  [X] it reverts with StalePrice
    function test_getTwoFeedPriceDiv_givenSecondFeedStalePrice_reverts(uint256 publishTime_) public {
        // Bound publish time to be stale (publishTime < block.timestamp - UPDATE_THRESHOLD)
        publishTime_ = bound(publishTime_, 0, block.timestamp - UPDATE_THRESHOLD - 1);
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the first feed expo + outputDecimals > BASE_10_MAX_EXPONENT
    //  [ ] it reverts with Pyth_ExponentOutOfBounds

    // given the first feed expo is negative (expo = -8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the first feed expo is positive (expo = 8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the first feed expo is zero (expo = 0, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the first feed expo equals negative outputDecimals (expo = -18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the first feed expo equals positive outputDecimals (expo = 18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the first feed expo is very negative (expo = -20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price by dividing

    // given the first feed expo is very positive (expo = 20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price by multiplying

    // given the first feed publish time is >= the threshold boundary
    //  [X] it returns the correct price
    function test_getTwoFeedPriceDiv_givenFirstFeedPublishTimeAboveThreshold(uint256 publishTime_) public {
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
        uint256 priceInt = pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);

        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(10 ** PRICE_DECIMALS, 500000000);
        assertEq(priceInt, expected, "Divided price should match expected when first feed at threshold");
    }

    // given the second feed expo + outputDecimals > BASE_10_MAX_EXPONENT
    //  [ ] it reverts with Pyth_ExponentOutOfBounds

    // given the second feed expo is negative (expo = -8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the second feed expo is positive (expo = 8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the second feed expo is zero (expo = 0, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the second feed expo equals negative outputDecimals (expo = -18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the second feed expo equals positive outputDecimals (expo = 18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the second feed expo is very negative (expo = -20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price by dividing

    // given the second feed expo is very positive (expo = 20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price by multiplying

    // given the second feed publish time is >= the threshold boundary
    //  [X] it returns the correct price
    function test_getTwoFeedPriceDiv_givenSecondFeedPublishTimeAboveThreshold(uint256 publishTime_) public {
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
        uint256 priceInt = pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);

        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(10 ** PRICE_DECIMALS, 500000000);
        assertEq(priceInt, expected, "Divided price should match expected when second feed at threshold");
    }

    // =========  TWO FEED TESTS - MUL ========= //

    // given all parameters are valid for two feeds
    //  [X] it returns the correct multiplied price (first * second) in output decimals
    function test_getTwoFeedPriceMul_success() public view {
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
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(500000000, 10 ** PRICE_DECIMALS);
        assertEq(priceInt, expected, "Multiplied price should match expected calculation");
    }

    // given the first pyth contract address is zero
    //  [X] it reverts with Pyth_ParamsPythInvalid
    function test_getTwoFeedPriceMul_revertsOnParamsFirstFeedInvalid() public {
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
    //  [ ] it reverts with Pyth_ParamsPythInvalid

    // given the first price feed ID is zero
    //  [ ] it reverts with Pyth_ParamsPriceFeedIdInvalid

    // given the second price feed ID is zero
    //  [ ] it reverts with Pyth_ParamsPriceFeedIdInvalid

    // given the first update threshold is zero
    //  [ ] it reverts with Pyth_ParamsUpdateThresholdInvalid

    // given the second update threshold is zero
    //  [ ] it reverts with Pyth_ParamsUpdateThresholdInvalid

    // given the first max confidence is zero
    //  [ ] it reverts with Pyth_ParamsMaxConfidenceInvalid

    // given the second max confidence is zero
    //  [ ] it reverts with Pyth_ParamsMaxConfidenceInvalid

    // given the first feed has invalid price (<= 0)
    //  [ ] it reverts with Pyth_FeedPriceInvalid

    // given the second feed has invalid price (<= 0)
    //  [ ] it reverts with Pyth_FeedPriceInvalid

    // given the first feed publish time is < the threshold boundary
    //  [X] it reverts with StalePrice
    function test_getTwoFeedPriceMul_givenFirstFeedStalePrice_reverts(uint256 publishTime_) public {
        // Bound publish time to be stale (publishTime < block.timestamp - UPDATE_THRESHOLD)
        publishTime_ = bound(publishTime_, 0, block.timestamp - UPDATE_THRESHOLD - 1);
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
    function test_getTwoFeedPriceMul_givenSecondFeedStalePrice_reverts(uint256 publishTime_) public {
        // Bound publish time to be stale (publishTime < block.timestamp - UPDATE_THRESHOLD)
        publishTime_ = bound(publishTime_, 0, block.timestamp - UPDATE_THRESHOLD - 1);
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

    // given the first feed expo + outputDecimals > BASE_10_MAX_EXPONENT
    //  [ ] it reverts with Pyth_ExponentOutOfBounds

    // given the first feed expo is negative (expo = -8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the first feed expo is positive (expo = 8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the first feed expo is zero (expo = 0, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the first feed expo equals negative outputDecimals (expo = -18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the first feed expo equals positive outputDecimals (expo = 18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the first feed expo is very negative (expo = -20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price by dividing

    // given the first feed expo is very positive (expo = 20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price by multiplying

    // given the first feed publish time is >= the threshold boundary
    //  [ ] it returns the correct price

    // given the second feed expo + outputDecimals > BASE_10_MAX_EXPONENT
    //  [ ] it reverts with Pyth_ExponentOutOfBounds

    // given the second feed expo is negative (expo = -8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the second feed expo is positive (expo = 8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the second feed expo is zero (expo = 0, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the second feed expo equals negative outputDecimals (expo = -18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the second feed expo equals positive outputDecimals (expo = 18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price

    // given the second feed expo is very negative (expo = -20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price by dividing

    // given the second feed expo is very positive (expo = 20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [ ] it reverts with Pyth_FeedConfidenceExcessive
    //  [ ] it correctly converts the price by multiplying

    // given the second feed publish time is >= the threshold boundary
    //  [ ] it returns the correct price
}
/// forge-lint: disable-end(mixed-case-variable,mixed-case-function)
