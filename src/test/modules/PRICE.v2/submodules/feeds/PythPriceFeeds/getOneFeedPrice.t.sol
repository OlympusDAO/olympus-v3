// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-variable,mixed-case-function)
pragma solidity >=0.8.0;

// Test
import {PythPriceFeedsTest} from "./PythPriceFeedsTest.sol";
import {MockPyth} from "src/test/mocks/MockPyth.sol";

// Interfaces
import {IPyth} from "src/interfaces/IPyth.sol";

// Bophades
import {PythPriceFeeds} from "src/modules/PRICE/submodules/feeds/PythPriceFeeds.sol";

contract PythPriceFeedsGetOneFeedPriceTest is PythPriceFeedsTest {
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

    // given the pyth contract returns data with incorrect length
    //  [X] it reverts with Pyth_FeedInvalid
    function test_getOneFeedPrice_returnDataLengthInvalid_reverts() public {
        address mockPyth = address(0xDEAD);

        // Mock the call to succeed but return data with wrong length (not 128 bytes)
        // The _PRICE_DATA_SIZE is 128 bytes, so we return something smaller
        bytes memory wrongLengthData = abi.encode(uint256(1), uint256(2)); // Only 64 bytes

        vm.mockCall(
            mockPyth,
            abi.encodeWithSelector(
                IPyth.getPriceNoOlderThan.selector,
                PRICE_ID_1,
                uint256(UPDATE_THRESHOLD)
            ),
            wrongLengthData
        );

        bytes memory err = abi.encodeWithSelector(
            PythPriceFeeds.Pyth_FeedInvalid.selector,
            mockPyth,
            PRICE_ID_1
        );
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(
            mockPyth,
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);

        vm.clearMockedCalls();
    }

    // given the pyth contract reverts with return data
    //  [X] it bubbles up the revert
    function test_getOneFeedPrice_pythRevertsWithData_bubblesUpRevert() public {
        address mockPyth = address(0xBEEF);

        // Create a custom error
        bytes memory customError = abi.encodeWithSignature(
            "CustomError(string)",
            "Test revert message"
        );

        // Mock the call to revert with data
        vm.mockCallRevert(
            mockPyth,
            abi.encodeWithSelector(
                IPyth.getPriceNoOlderThan.selector,
                PRICE_ID_1,
                uint256(UPDATE_THRESHOLD)
            ),
            customError
        );

        // Expect the revert to bubble up
        vm.expectRevert(customError);

        bytes memory params = encodeOneFeedParams(
            mockPyth,
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

    // given the price feed is not found
    //  [X] it reverts with PriceFeedNotFound
    function test_getOneFeedPrice_priceFeedNotFound_reverts() public {
        bytes memory err = abi.encodeWithSelector(MockPyth.PriceFeedNotFound.selector);
        vm.expectRevert(err);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000001),
            UPDATE_THRESHOLD,
            MAX_CONFIDENCE
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    // given the publish time is before the update threshold
    //  [X] it reverts with StalePrice
    function test_getOneFeedPrice_givenStalePrice_reverts(uint256 publishTime_) public {
        // Bound publish time to be stale (publishTime < block.timestamp - UPDATE_THRESHOLD)
        publishTime_ = bound(publishTime_, 1, block.timestamp - UPDATE_THRESHOLD - 1);
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
        // Bound expo to be positive (> 0) to test Pyth_ExponentPositive error
        // Keep expo within reasonable range [1, 32] to avoid overflow in calculations
        expo_ = int32(bound(int256(expo_), 1, 32));
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

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            maxConfidence
        );
        pythSubmodule.getOneFeedPrice(address(0), PRICE_DECIMALS, params);
    }

    //  [X] it correctly converts the price
    function test_getOneFeedPrice_expoZero() public {
        // expo = 0, outputDecimals = 18, totalExponent = 18
        int64 price = 123456789;
        int32 expo = 0;
        pyth.setPrice(PRICE_ID_1, price, 1, expo, block.timestamp);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            type(uint64).max // Ensures confidence interval is below the maximum
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
    function test_getOneFeedPrice_expoEqualsNegativeOutputDecimals() public {
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
            /// forge-lint: disable-next-line(unsafe-typecast)
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
    function test_getOneFeedPrice_expoVeryNegative() public {
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

    // given the confidence interval is <= the maximum
    //  [X] it correctly converts the price
    function test_getOneFeedPrice_confidenceBelowMaximum(uint64 priceConfidence_) public {
        // expo = -8, outputDecimals = 18
        // confidenceExponent = 18 + (-8) = 10
        // maxConfidenceInPythScale = maxConfidence / 10^10 = 2e16 / 1e10 = 2e6
        // Test with confidence below maximum threshold (1 <= confidence <= 2e6)
        priceConfidence_ = uint64(bound(priceConfidence_, 1, 2e6));
        pyth.setPrice(PRICE_ID_1, PRICE_1, priceConfidence_, EXPO_1, block.timestamp);

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

    // given the publish time equals exactly the update threshold boundary
    //  [X] it returns the correct price
    function test_getOneFeedPrice_publishTimeExactlyAtThreshold() public {
        // Set publish time to exactly block.timestamp - UPDATE_THRESHOLD
        // This tests the boundary condition: publishTime == blockTimestamp - updateThreshold
        // The validation checks: publishTime < blockTimestamp - updateThreshold (strict <)
        // So when publishTime == blockTimestamp - updateThreshold, it should pass
        uint256 publishTime = block.timestamp - UPDATE_THRESHOLD;
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, publishTime);

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
            "Price should be valid when publish time exactly equals threshold boundary"
        );
    }

    // given outputDecimals is different from default (18)
    //  [X] it correctly converts prices to the specified output decimals
    function test_getOneFeedPrice_outputDecimalsFuzz(uint8 outputDecimals_) public {
        // Bound output decimals to reasonable range [8, 36] to avoid rounding issues and overflow
        // Using >= 8 ensures we don't lose precision (expo = -8)
        outputDecimals_ = uint8(bound(outputDecimals_, 8, 36));
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals_) / 10 ** 18 // scale max confidence to the new output decimals
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), outputDecimals_, params);

        // expo = -8, price = 123456789, outputDecimals = outputDecimals_
        // Conversion formula: price * 10^outputDecimals / 10^(-expo) = price * 10^outputDecimals / 10^8
        // = 123456789 * 10^(outputDecimals_ - 8)
        /// forge-lint: disable-next-line(unsafe-typecast)
        uint256 expected = uint256(uint64(PRICE_1)) * 10 ** (outputDecimals_ - 8);
        assertEq(priceInt, expected, "Price should match expected for fuzzed output decimals");
    }

    // given outputDecimals is < the expo
    //  given the price is < 1
    //   [X] the price loses precision
    function test_getOneFeedPrice_outputDecimalsLessThanExpo_priceLessThanOne() public {
        // Bound output decimals to 6, which is less than the expo (8)
        uint8 outputDecimals = 6;
        // Set the price to 23456789 (0.23456789 * 10^8)
        pyth.setPrice(PRICE_ID_1, 23456789, CONF_1, EXPO_1, block.timestamp);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18 // scale max confidence to the new output decimals
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), outputDecimals, params);

        // expo = -8, price = 23456789 (0.23456789 * 10^8)
        // outputDecimals = 6, price = 234567 (0.234567 * 10^6)
        uint256 expected = 234567;
        assertEq(priceInt, expected, "Price should lose precision");
    }

    //  given the price rounds down to 0
    //   [X] it returns zero
    function test_getOneFeedPrice_outputDecimalsLessThanExpo_priceRoundsDownToZero() public {
        // Bound output decimals to 6, which is less than the expo (8)
        uint8 outputDecimals = 6;
        // Set the price to 89 (0.00000089 * 10^8)
        // This will round down to 0 when converted to output decimals
        pyth.setPrice(PRICE_ID_1, 89, CONF_1, EXPO_1, block.timestamp);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18 // scale max confidence to the new output decimals
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), outputDecimals, params);

        // expo = -8, price = 89 (0.00000089 * 10^8)
        // outputDecimals = 6, price = 0 (89 * 10^6 / 10^8 is less than 1)
        uint256 expected = 0;
        assertEq(priceInt, expected, "Price should round down to zero");
    }

    //  [X] the price loses precision
    function test_getOneFeedPrice_outputDecimalsLessThanExpo() public {
        // Bound output decimals to 6, which is less than the expo (8)
        uint8 outputDecimals = 6;
        pyth.setPrice(PRICE_ID_1, PRICE_1, CONF_1, EXPO_1, block.timestamp);

        bytes memory params = encodeOneFeedParams(
            address(pyth),
            PRICE_ID_1,
            UPDATE_THRESHOLD,
            (MAX_CONFIDENCE * 10 ** outputDecimals) / 10 ** 18 // scale max confidence to the new output decimals
        );
        uint256 priceInt = pythSubmodule.getOneFeedPrice(address(0), outputDecimals, params);

        // expo = -8, price = 123456789 (1.23456789 * 10^8)
        // outputDecimals = 6, price = 1234567 (1.234567 * 10^6)
        uint256 expected = 1234567;
        assertEq(priceInt, expected, "Price should lose precision");
    }
}
/// forge-lint: disable-end(mixed-case-variable,mixed-case-function)
