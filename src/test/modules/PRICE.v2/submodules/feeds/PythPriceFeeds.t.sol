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
    function test_getOneFeedPrice_pythZero_reverts() public {
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
    function test_getOneFeedPrice_priceFeedIdZero_reverts() public {
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
    function test_getOneFeedPrice_updateThresholdZero_reverts() public {
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
    function test_getOneFeedPrice_maxConfidenceZero_reverts() public {
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
    function test_getOneFeedPrice_exponentOutOfBounds_reverts(int32 expo_) public {
        // Set expo such that expo + outputDecimals > BASE_10_MAX_EXPONENT
        // expo must be > BASE_10_MAX_EXPONENT - outputDecimals = 50 - 18 = 32
        expo_ = int32(
            bound(
                int256(expo_),
                int32(int8(BASE_10_MAX_EXPONENT) - int8(PRICE_DECIMALS) + 1),
                type(int32).max
            )
        );
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, expo_, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ExponentOutOfBounds.selector,
            address(pyth),
            PRICE_ID_1,
            expo_,
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
    function test_getOneFeedPrice_pythContractInvalid_reverts() public {
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

    // given the price is <= 0
    //  [X] it reverts with Pyth_FeedPriceInvalid
    function test_getOneFeedPrice_feedPriceInvalid_reverts(int64 price_) public {
        price_ = int64(bound(price_, type(int64).min, 0));
        pyth.setPrice(PRICE_ID_1, price_, CONF_1, EXPO_1, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedPriceInvalid.selector,
            address(pyth),
            PRICE_ID_1,
            price_
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

    // given expo is positive (expo > 0)
    //  [X] it reverts with Pyth_ExponentPositive
    function test_getOneFeedPrice_expoPositive_reverts(int32 expo_) public {
        // Bound expo to be positive (> 0) but not so large it triggers ExponentOutOfBounds first
        // expo + outputDecimals <= BASE_10_MAX_EXPONENT, so expo <= 50 - 18 = 32
        // But we want to test positive expo, so expo in range [1, 32]
        expo_ = int32(
            bound(
                int256(expo_),
                1,
                int256(uint256(BASE_10_MAX_EXPONENT)) - int256(uint256(PRICE_DECIMALS))
            )
        );
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, expo_, block.timestamp);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
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

        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // given expo is zero (expo = 0, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getOneFeedPrice_expoZero_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = 0, outputDecimals = 18
        // confidenceExponent = 18 + 0 = 18
        // Use a higher maxConfidence to get a meaningful threshold
        // maxConfidence = 1e19 -> maxConfidenceInPythScale = 1e19 / 1e18 = 10
        uint64 maxConfidence = 1e19;
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

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            maxConfidence
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

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

    // given expo equals negative outputDecimals (expo = -18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getOneFeedPrice_expoEqualsNegativeOutputDecimals_maxConfidenceExceeded_reverts(
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

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

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
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getOneFeedPrice_expoVeryNegative_maxConfidenceExceeded_reverts(
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

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

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
        publishTime_ = uint48(
            bound(publishTime_, block.timestamp - UPDATE_THRESHOLD, block.timestamp)
        );
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
    function test_getTwoFeedPriceDiv_firstPythZero_reverts() public {
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
    function test_getTwoFeedPriceDiv_firstPriceFeedIdZero_reverts() public {
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
    function test_getTwoFeedPriceDiv_firstUpdateThresholdZero_reverts() public {
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
    function test_getTwoFeedPriceDiv_firstMaxConfidenceZero_reverts() public {
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
    function test_getTwoFeedPriceDiv_secondPythZero_reverts() public {
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
    function test_getTwoFeedPriceDiv_secondPriceFeedIdZero_reverts() public {
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
    function test_getTwoFeedPriceDiv_secondUpdateThresholdZero_reverts() public {
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
    function test_getTwoFeedPriceDiv_secondMaxConfidenceZero_reverts() public {
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
    function test_getTwoFeedPriceDiv_firstFeedPriceInvalid_reverts(int64 price_) public {
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the second feed has invalid price (<= 0)
    //  [X] it reverts with Pyth_FeedPriceInvalid
    function test_getTwoFeedPriceDiv_secondFeedPriceInvalid_reverts(int64 price_) public {
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
    function test_getTwoFeedPriceDiv_givenSecondFeedStalePrice_reverts(
        uint256 publishTime_
    ) public {
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
    //  [X] it reverts with Pyth_ExponentOutOfBounds
    function test_getTwoFeedPriceDiv_givenFirstFeedExponentOutOfBounds_reverts(int32 expo_) public {
        // Set expo such that expo + outputDecimals > BASE_10_MAX_EXPONENT
        // expo must be > BASE_10_MAX_EXPONENT - outputDecimals = 50 - 18 = 32
        expo_ = int32(
            bound(
                int256(expo_),
                int32(int8(BASE_10_MAX_EXPONENT) - int8(PRICE_DECIMALS) + 1),
                type(int32).max
            )
        );
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, expo_, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ExponentOutOfBounds.selector,
            address(pyth),
            PRICE_ID_1,
            expo_,
            PRICE_DECIMALS,
            BASE_10_MAX_EXPONENT
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

    // given the first feed expo is negative (expo = -8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getTwoFeedPriceDiv_givenFirstFeedExpoNegative_maxConfidenceExceeded_reverts(
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_getTwoFeedPriceDiv_givenFirstFeedExpoNegative() public view {
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
        uint256 priceInt = pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);

        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(10 ** PRICE_DECIMALS, 500000000);
        assertEq(priceInt, expected, "Price should match expected for negative expo first feed");
    }

    // given the first feed expo is positive (expo > 0)
    //  [X] it reverts with Pyth_ExponentPositive
    function test_getTwoFeedPriceDiv_givenFirstFeedExpoPositive_reverts(int32 expo_) public {
        // Bound expo to be positive (> 0) but not so large it triggers ExponentOutOfBounds first
        // expo + outputDecimals <= BASE_10_MAX_EXPONENT, so expo <= 50 - 18 = 32
        // But we want to test positive expo, so expo in range [1, 32]
        expo_ = int32(
            bound(
                int256(expo_),
                1,
                int256(uint256(BASE_10_MAX_EXPONENT)) - int256(uint256(PRICE_DECIMALS))
            )
        );
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

        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the first feed expo is zero (expo = 0, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getTwoFeedPriceDiv_givenFirstFeedExpoZero_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = 0, outputDecimals = 18
        // confidenceExponent = 18 + 0 = 18
        // Use a higher maxConfidence to get a meaningful threshold
        // maxConfidence = 1e19 -> maxConfidenceInPythScale = 1e19 / 1e18 = 10
        uint64 maxConfidence = 1e19;
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_getTwoFeedPriceDiv_givenFirstFeedExpoZero() public {
        // First feed: expo = 0, price = 100 -> 100 * 10^18
        int64 price = 100;
        int32 expo = 0;
        pyth.setPrice(PRICE_ID_1, price, 0, expo, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            type(uint64).max,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);

        // First: 100 * 10^18, Second: 500000000 (18 dec)
        // Result: (100 * 10^18 * 10^18) / 500000000 = 100 * 10^36 / 5e8 = 2 * 10^29
        uint256 firstPrice = uint256(100) * 10 ** 18;
        uint256 expected = firstPrice.mulDiv(10 ** PRICE_DECIMALS, 500000000);
        assertEq(priceInt, expected, "Price should match expected for zero expo first feed");
    }

    // given the first feed expo equals negative outputDecimals (expo = -18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getTwoFeedPriceDiv_givenFirstFeedExpoNegativeEqualsOutputDecimals_maxConfidenceExceeded_reverts(
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_getTwoFeedPriceDiv_givenFirstFeedExpoNegativeEqualsOutputDecimals() public {
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
        uint256 priceInt = pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);

        // First: 1e9, Second: 500000000 (18 dec)
        // Result: (1e9 * 10^18) / 500000000 = 1e27 / 5e8 = 2e18
        uint256 firstPrice = uint256(1e9);
        uint256 expected = firstPrice.mulDiv(10 ** PRICE_DECIMALS, 500000000);
        assertEq(
            priceInt,
            expected,
            "Price should match expected when first feed expo equals negative outputDecimals"
        );
    }

    // given the first feed expo is very negative (expo = -20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getTwoFeedPriceDiv_givenFirstFeedExpoVeryNegative_maxConfidenceExceeded_reverts(
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price by dividing
    function test_getTwoFeedPriceDiv_givenFirstFeedExpoVeryNegative() public {
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
        uint256 priceInt = pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);

        // First: 1e10 / 100 = 1e8, Second: 500000000 (18 dec)
        // Result: (1e8 * 10^18) / 500000000 = 1e26 / 5e8 = 2e17
        uint256 firstPrice = uint256(1e10) / 100;
        uint256 expected = firstPrice.mulDiv(10 ** PRICE_DECIMALS, 500000000);
        assertEq(
            priceInt,
            expected,
            "Price should match expected for very negative expo first feed"
        );
    }

    // given the first feed publish time is >= the threshold boundary
    //  [X] it returns the correct price
    function test_getTwoFeedPriceDiv_givenFirstFeedPublishTimeAboveThreshold(
        uint256 publishTime_
    ) public {
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
        assertEq(
            priceInt,
            expected,
            "Divided price should match expected when first feed at threshold"
        );
    }

    // given the second feed expo + outputDecimals > BASE_10_MAX_EXPONENT
    //  [X] it reverts with Pyth_ExponentOutOfBounds
    function test_getTwoFeedPriceDiv_givenSecondFeedExponentOutOfBounds_reverts(
        int32 expo_
    ) public {
        // Set expo such that expo + outputDecimals > BASE_10_MAX_EXPONENT
        // expo must be > BASE_10_MAX_EXPONENT - outputDecimals = 50 - 18 = 32
        expo_ = int32(
            bound(
                int256(expo_),
                int32(int8(BASE_10_MAX_EXPONENT) - int8(PRICE_DECIMALS) + 1),
                type(int32).max
            )
        );
        pyth.setPrice(PRICE_ID_3, PRICE_3, CONF_3, expo_, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ExponentOutOfBounds.selector,
            address(pyth),
            PRICE_ID_3,
            expo_,
            PRICE_DECIMALS,
            BASE_10_MAX_EXPONENT
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

    // given the second feed expo is negative (expo = -8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getTwoFeedPriceDiv_givenSecondFeedExpoNegative_maxConfidenceExceeded_reverts(
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_getTwoFeedPriceDiv_givenSecondFeedExpoNegative() public {
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
        uint256 priceInt = pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);

        // First: 1234567890000000000 (18 dec), Second: 1234567890000000000
        // Result: (1234567890000000000 * 10^18) / 1234567890000000000 = 10^18
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(
            10 ** PRICE_DECIMALS,
            EXPECTED_PRICE_1_18_DEC
        );
        assertEq(priceInt, expected, "Price should match expected for negative expo second feed");
    }

    // given the second feed expo is positive (expo > 0)
    //  [X] it reverts with Pyth_ExponentPositive
    function test_getTwoFeedPriceDiv_givenSecondFeedExpoPositive_reverts(int32 expo_) public {
        // Bound expo to be positive (> 0) but not so large it triggers ExponentOutOfBounds first
        // expo + outputDecimals <= BASE_10_MAX_EXPONENT, so expo <= 50 - 18 = 32
        // But we want to test positive expo, so expo in range [1, 32]
        expo_ = int32(
            bound(
                int256(expo_),
                1,
                int256(uint256(BASE_10_MAX_EXPONENT)) - int256(uint256(PRICE_DECIMALS))
            )
        );
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

        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    // given the second feed expo is zero (expo = 0, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getTwoFeedPriceDiv_givenSecondFeedExpoZero_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = 0, outputDecimals = 18
        // confidenceExponent = 18 + 0 = 18
        // Use a higher maxConfidence to get a meaningful threshold
        // maxConfidence = 1e19 -> maxConfidenceInPythScale = 1e19 / 1e18 = 10
        uint64 maxConfidence = 1e19;
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_getTwoFeedPriceDiv_givenSecondFeedExpoZero() public {
        // Second feed: expo = 0, price = 100 -> 100 * 10^18
        int64 price = 100;
        int32 expo = 0;
        pyth.setPrice(PRICE_ID_3, price, 0, expo, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            type(uint64).max
        );
        uint256 priceInt = pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);

        // First: 1234567890000000000 (18 dec), Second: 100 * 10^18
        // Result: (1234567890000000000 * 10^18) / (100 * 10^18) = 12345678900000000
        uint256 secondPrice = uint256(100) * 10 ** 18;
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(10 ** PRICE_DECIMALS, secondPrice);
        assertEq(priceInt, expected, "Price should match expected for zero expo second feed");
    }

    // given the second feed expo equals negative outputDecimals (expo = -18, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getTwoFeedPriceDiv_givenSecondFeedExpoNegativeEqualsOutputDecimals_maxConfidenceExceeded_reverts(
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_getTwoFeedPriceDiv_givenSecondFeedExpoNegativeEqualsOutputDecimals() public {
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
        uint256 priceInt = pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);

        // First: 1234567890000000000 (18 dec), Second: 1e9
        // Result: (1234567890000000000 * 10^18) / 1e9 = 1234567890000000000000000000
        uint256 secondPrice = uint256(1e9);
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(10 ** PRICE_DECIMALS, secondPrice);
        assertEq(
            priceInt,
            expected,
            "Price should match expected when second feed expo equals negative outputDecimals"
        );
    }

    // given the second feed expo is very negative (expo = -20, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getTwoFeedPriceDiv_givenSecondFeedExpoVeryNegative_maxConfidenceExceeded_reverts(
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
        pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price by dividing
    function test_getTwoFeedPriceDiv_givenSecondFeedExpoVeryNegative() public {
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
        uint256 priceInt = pythSubmodule.getTwoFeedPriceDiv(address(0), PRICE_DECIMALS, params);

        // First: 1234567890000000000 (18 dec), Second: 1e8
        // Result: (1234567890000000000 * 10^18) / 1e8
        uint256 secondPrice = uint256(1e10) / 100;
        uint256 expected = EXPECTED_PRICE_1_18_DEC.mulDiv(10 ** PRICE_DECIMALS, secondPrice);
        assertEq(
            priceInt,
            expected,
            "Price should match expected for very negative expo second feed"
        );
    }

    // given the second feed publish time is >= the threshold boundary
    //  [X] it returns the correct price
    function test_getTwoFeedPriceDiv_givenSecondFeedPublishTimeAboveThreshold(
        uint256 publishTime_
    ) public {
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
        assertEq(
            priceInt,
            expected,
            "Divided price should match expected when second feed at threshold"
        );
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
    function test_getTwoFeedPriceMul_firstPythZero_reverts() public {
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
    function test_getTwoFeedPriceMul_secondPythZero_reverts() public {
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
    function test_getTwoFeedPriceMul_firstPriceFeedIdZero_reverts() public {
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
    function test_getTwoFeedPriceMul_secondPriceFeedIdZero_reverts() public {
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
    function test_getTwoFeedPriceMul_firstUpdateThresholdZero_reverts() public {
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
    function test_getTwoFeedPriceMul_secondUpdateThresholdZero_reverts() public {
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
    function test_getTwoFeedPriceMul_firstMaxConfidenceZero_reverts() public {
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
    function test_getTwoFeedPriceMul_secondMaxConfidenceZero_reverts() public {
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
    function test_getTwoFeedPriceMul_firstFeedPriceInvalid_reverts(int64 price_) public {
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
    function test_getTwoFeedPriceMul_secondFeedPriceInvalid_reverts(int64 price_) public {
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
    function test_getTwoFeedPriceMul_givenSecondFeedStalePrice_reverts(
        uint256 publishTime_
    ) public {
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
    //  [X] it reverts with Pyth_ExponentOutOfBounds
    function test_getTwoFeedPriceMul_givenFirstFeedExponentOutOfBounds_reverts(int32 expo_) public {
        // Set expo such that expo + outputDecimals > BASE_10_MAX_EXPONENT
        // expo must be > BASE_10_MAX_EXPONENT - outputDecimals = 50 - 18 = 32
        expo_ = int32(
            bound(
                int256(expo_),
                int32(int8(BASE_10_MAX_EXPONENT) - int8(PRICE_DECIMALS) + 1),
                type(int32).max
            )
        );
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, expo_, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ExponentOutOfBounds.selector,
            address(pyth),
            PRICE_ID_1,
            expo_,
            PRICE_DECIMALS,
            BASE_10_MAX_EXPONENT
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

    // given the first feed expo is negative (expo = -8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getTwoFeedPriceMul_givenFirstFeedExpoNegative_maxConfidenceExceeded_reverts(
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
    function test_getTwoFeedPriceMul_givenFirstFeedExpoNegative() public view {
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
    function test_getTwoFeedPriceMul_givenFirstFeedExpoPositive_reverts(int32 expo_) public {
        // Bound expo to be positive (> 0) but not so large it triggers ExponentOutOfBounds first
        // expo + outputDecimals <= BASE_10_MAX_EXPONENT, so expo <= 50 - 18 = 32
        // But we want to test positive expo, so expo in range [1, 32]
        expo_ = int32(
            bound(
                int256(expo_),
                1,
                int256(uint256(BASE_10_MAX_EXPONENT)) - int256(uint256(PRICE_DECIMALS))
            )
        );
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
    function test_getTwoFeedPriceMul_givenFirstFeedExpoZero_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = 0, outputDecimals = 18
        // confidenceExponent = 18 + 0 = 18
        // Use a higher maxConfidence to get a meaningful threshold
        // maxConfidence = 1e19 -> maxConfidenceInPythScale = 1e19 / 1e18 = 10
        uint64 maxConfidence = 1e19;
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
    function test_getTwoFeedPriceMul_givenFirstFeedExpoZero() public {
        // First feed: expo = 0, price = 100 -> 100 * 10^18
        int64 price = 100;
        int32 expo = 0;
        pyth.setPrice(PRICE_ID_1, price, 0, expo, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            type(uint64).max,
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
    function test_getTwoFeedPriceMul_givenFirstFeedExpoNegativeEqualsOutputDecimals_maxConfidenceExceeded_reverts(
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
    function test_getTwoFeedPriceMul_givenFirstFeedExpoNegativeEqualsOutputDecimals() public {
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
    function test_getTwoFeedPriceMul_givenFirstFeedExpoVeryNegative_maxConfidenceExceeded_reverts(
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
    function test_getTwoFeedPriceMul_givenFirstFeedExpoVeryNegative() public {
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
    function test_getTwoFeedPriceMul_givenFirstFeedPublishTimeAboveThreshold(
        uint256 publishTime_
    ) public {
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

    // given the second feed expo + outputDecimals > BASE_10_MAX_EXPONENT
    //  [X] it reverts with Pyth_ExponentOutOfBounds
    function test_getTwoFeedPriceMul_givenSecondFeedExponentOutOfBounds_reverts(
        int32 expo_
    ) public {
        // Set expo such that expo + outputDecimals > BASE_10_MAX_EXPONENT
        // expo must be > BASE_10_MAX_EXPONENT - outputDecimals = 50 - 18 = 32
        expo_ = int32(
            bound(
                int256(expo_),
                int32(int8(BASE_10_MAX_EXPONENT) - int8(PRICE_DECIMALS) + 1),
                type(int32).max
            )
        );
        pyth.setPrice(PRICE_ID_3, PRICE_3, CONF_3, expo_, block.timestamp);

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_ExponentOutOfBounds.selector,
            address(pyth),
            PRICE_ID_3,
            expo_,
            PRICE_DECIMALS,
            BASE_10_MAX_EXPONENT
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

    // given the second feed expo is negative (expo = -8, outputDecimals = 18)
    //  given the confidence interval is above the maximum
    //   [X] it reverts with Pyth_FeedConfidenceExcessive
    function test_getTwoFeedPriceMul_givenSecondFeedExpoNegative_maxConfidenceExceeded_reverts(
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
    function test_getTwoFeedPriceMul_givenSecondFeedExpoNegative() public {
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
    function test_getTwoFeedPriceMul_givenSecondFeedExpoPositive_reverts(int32 expo_) public {
        // Bound expo to be positive (> 0) but not so large it triggers ExponentOutOfBounds first
        // expo + outputDecimals <= BASE_10_MAX_EXPONENT, so expo <= 50 - 18 = 32
        // But we want to test positive expo, so expo in range [1, 32]
        expo_ = int32(
            bound(
                int256(expo_),
                1,
                int256(uint256(BASE_10_MAX_EXPONENT)) - int256(uint256(PRICE_DECIMALS))
            )
        );
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
    function test_getTwoFeedPriceMul_givenSecondFeedExpoZero_maxConfidenceExceeded_reverts(
        uint64 priceConfidence_
    ) public {
        // expo = 0, outputDecimals = 18
        // confidenceExponent = 18 + 0 = 18
        // Use a higher maxConfidence to get a meaningful threshold
        // maxConfidence = 1e19 -> maxConfidenceInPythScale = 1e19 / 1e18 = 10
        uint64 maxConfidence = 1e19;
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
    function test_getTwoFeedPriceMul_givenSecondFeedExpoZero() public {
        // Second feed: expo = 0, price = 100 -> 100 * 10^18
        int64 price = 100;
        int32 expo = 0;
        pyth.setPrice(PRICE_ID_3, price, 0, expo, block.timestamp);

        bytes memory params = encodeTwoFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE,
            address(pyth),
            PRICE_ID_3,
            UPDATE_THRESHOLD,
            type(uint64).max
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
    function test_getTwoFeedPriceMul_givenSecondFeedExpoNegativeEqualsOutputDecimals_maxConfidenceExceeded_reverts(
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
    function test_getTwoFeedPriceMul_givenSecondFeedExpoNegativeEqualsOutputDecimals() public {
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
    function test_getTwoFeedPriceMul_givenSecondFeedExpoVeryNegative_maxConfidenceExceeded_reverts(
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
    function test_getTwoFeedPriceMul_givenSecondFeedExpoVeryNegative() public {
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
    function test_getTwoFeedPriceMul_givenSecondFeedPublishTimeAboveThreshold(
        uint256 publishTime_
    ) public {
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
}
/// forge-lint: disable-end(mixed-case-variable,mixed-case-function)
