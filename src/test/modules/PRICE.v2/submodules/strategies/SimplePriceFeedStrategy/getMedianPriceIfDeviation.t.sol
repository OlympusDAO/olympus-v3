// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

/// @title Tests for getMedianPriceIfDeviation function
/// @notice Tests the deviation-based median price strategy
contract SimplePriceFeedStrategyGetMedianPriceIfDeviationTest is SimplePriceFeedStrategyBase {
    // =========  TESTS ========= //

    // ========== CONFIGURATION ERRORS ========== //
    // when input array length is less than 3
    //   [X] it reverts
    // when params are empty
    //   [X] it reverts
    // when params length is not 64 bytes
    //   [X] it reverts
    // when deviationBps is 0
    //   [X] it reverts
    // when deviationBps is 10000 or greater
    //   [X] it reverts

    function test_whenInvalidArrayLength_reverts(uint8 len_) public {
        uint8 len = uint8(bound(len_, 0, 2));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(len, 3);
        strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(uint16(100), false));
    }

    function test_whenEmptyParams_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.001e18;
        prices[2] = 1.002e18;

        _expectRevertParams("");
        strategy.getMedianPriceIfDeviation(prices, "");
    }

    function test_whenInvalidParamsLength_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.001e18;
        prices[2] = 1.002e18;

        bytes memory invalidParams = abi.encode(uint256(123)); // 32 bytes
        _expectRevertParams(invalidParams);
        strategy.getMedianPriceIfDeviation(prices, invalidParams);
    }

    function test_whenDeviationBpsZero_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.001e18;
        prices[2] = 1.002e18;

        _expectRevertParams(_encodeDeviationParams(uint16(0), false));
        strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(uint16(0), false));
    }

    function test_whenDeviationBpsTooLarge_reverts(uint16 deviationBps_) public {
        uint16 deviationBps = uint16(bound(deviationBps_, DEVIATION_MAX + 1, 65_535));

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.001e18;
        prices[2] = 1.002e18;

        bytes memory params = _encodeDeviationParams(deviationBps, false);
        _expectRevertParams(params);
        strategy.getMedianPriceIfDeviation(prices, params);
    }

    // ========== ALL PRICES ZERO ========== //
    // when all prices are zero
    //   [X] it reverts

    function test_whenAllPricesZero_reverts(uint8 len_) public {
        uint8 len = uint8(bound(len_, 3, 10));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(0, 3);
        strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(uint16(100), false));
    }

    // ========== ONE NON-ZERO PRICE ========== //
    // when one non-zero price
    //   when strict mode is enabled
    //     [X] it reverts
    //   when strict mode is disabled
    //     [X] it returns that price

    function test_whenOneNonZeroPrice_strictMode_reverts(uint8 arrayLen_) public {
        uint8 arrayLen = uint8(bound(arrayLen_, 3, 10));
        uint256[] memory prices = new uint256[](arrayLen);
        prices[arrayLen - 1] = 1.5e18;

        _expectRevertPriceCount(1, 3);
        strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(uint16(100), true));
    }

    function test_whenOneNonZeroPrice_bestEffortMode(uint8 arrayLen_) public view {
        uint8 arrayLen = uint8(bound(arrayLen_, 3, 10));
        uint256[] memory prices = new uint256[](arrayLen);
        prices[arrayLen - 1] = 1.5e18;

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), false)
        );
        assertEq(price, 1.5e18, "should return the single non-zero price");
    }

    // ========== TWO NON-ZERO PRICES ========== //
    // when there are two non-zero prices
    //   when two prices deviate
    //     when strict mode is enabled
    //       [X] it reverts
    //     when strict mode is disabled
    //       [X] it returns the average
    //   when two prices do not deviate
    //     [X] it returns the first price

    function test_whenTwoNonZeroPrices_whenDeviating_whenStrictMode_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 2e18;

        _expectRevertPriceCount(2, 3);
        strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(uint16(100), true));
    }

    function test_whenTwoNonZeroPrices_whenDeviating_whenBestEffortMode() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 2e18;

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), false)
        );
        // 100% deviation > 1% threshold, so returns average = 1.5e18
        assertEq(price, 1.5e18, "should return average when two non-zero prices deviate");
    }

    function test_whenTwoNonZeroPrices_whenNotDeviating_bestEffortMode() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 1.001e18; // 0.1% deviation

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), false)
        );
        // 0.1% deviation < 1% threshold, so returns first price (min after sort)
        assertEq(price, 1e18, "should return first price when two prices don't deviate");
    }

    function test_whenTwoNonZeroPrices_whenNotDeviating_strictMode_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 1.001e18; // 0.1% deviation

        _expectRevertPriceCount(2, 3);
        strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(uint16(100), true));
    }

    // ========== THREE+ NON-ZERO PRICES WITH DEVIATION ========== //
    // when there are three non-zero prices
    //   when a price deviates from the average
    //     when strict mode is enabled
    //       [X] it returns the median
    //     when strict mode is disabled
    //       [X] it returns the median
    //   when no price deviates
    //     [X] it returns the first non-zero price

    function test_whenThreeNonZeroPrices_whenMinDeviating(uint8 mode_) public view {
        mode_ = uint8(bound(mode_, 0, 1));
        bool strictMode = mode_ == 0;

        uint256[] memory prices = new uint256[](4);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 1.2e18; // > 1% deviation from average
        prices[3] = 1.001e18;

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), strictMode)
        );
        // median of [1e18, 1.001e18, 1.2e18] = 1.001e18
        assertEq(price, 1.001e18, "should return median when min deviates");
    }

    function test_whenThreeNonZeroPrices_whenMaxDeviating(uint8 mode_) public view {
        mode_ = uint8(bound(mode_, 0, 1));
        bool strictMode = mode_ == 0;

        uint256[] memory prices = new uint256[](4);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 1.001e18;
        prices[3] = 1.2e18; // > 1% deviation from average

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), strictMode)
        );
        // median of [1e18, 1.001e18, 1.2e18] = 1.001e18
        assertEq(price, 1.001e18, "should return median when max deviates");
    }

    function test_whenThreeNonZeroPrices_whenNotDeviating(uint8 mode_) public view {
        mode_ = uint8(bound(mode_, 0, 1));
        bool strictMode = mode_ == 0;

        uint256[] memory prices = new uint256[](4);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 1.001e18; // < 1% deviation
        prices[3] = 1.002e18; // < 1% deviation

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), strictMode)
        );
        // No deviation, returns first non-zero price
        assertEq(price, 1e18, "should return first price when no deviation");
    }

    function test_whenFourPrices_whenDeviating(uint8 mode_) public view {
        mode_ = uint8(bound(mode_, 0, 1));
        bool strictMode = mode_ == 0;

        uint256[] memory prices = new uint256[](4);
        prices[0] = 1e18;
        prices[1] = 1.2e18; // > 1% deviation
        prices[2] = 1.001e18;
        prices[3] = 0.99e18;

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), strictMode)
        );
        // median of [0.99e18, 1e18, 1.001e18, 1.2e18] = (1e18 + 1.001e18) / 2
        assertEq(price, (1e18 + 1.001e18) / 2, "should return median of 4 prices");
    }

    // ========== FUZZ TESTS ========== //

    function test_whenThreePrices_whenDeviating_fuzz(
        uint256 basePrice_,
        uint256 deviationAmount_
    ) public view {
        uint16 deviationBps = 100; // 1%
        // Base price between 0.5e18 and 1.5e18
        uint256 basePrice = bound(basePrice_, 0.5e18, 1.5e18);
        // Deviation amount between 2% and 100% of base price (ensures deviation detected)
        uint256 deviationAmount = bound(deviationAmount_, basePrice / 50, basePrice);

        uint256[] memory prices = new uint256[](3);
        prices[0] = basePrice;
        prices[1] = basePrice + deviationAmount; // Deviates from average
        prices[2] = basePrice;

        // Sorted: [basePrice, basePrice, basePrice + deviationAmount]
        // Median = basePrice (middle element after sort)
        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        assertEq(price, basePrice, "should return median when deviation detected");
    }

    function test_whenThreePrices_whenNotDeviating_fuzz(
        uint256 basePrice_,
        uint256 smallVariance_
    ) public view {
        uint16 deviationBps = 100; // 1%
        // Base price between 0.5e18 and 1.5e18
        uint256 basePrice = bound(basePrice_, 0.5e18, 1.5e18);
        // Small variance less than 0.5% of base price (ensures no deviation)
        uint256 smallVariance = bound(smallVariance_, 0, basePrice / 200);

        uint256[] memory prices = new uint256[](3);
        prices[0] = basePrice;
        prices[1] = basePrice + smallVariance;
        prices[2] = basePrice;

        // No deviation, returns first non-zero price (basePrice)
        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        assertEq(price, basePrice, "should return first price when no deviation");
    }

    function test_whenOnePriceZero_whenNotDeviating_fuzz(uint8 priceZeroIndex_) public view {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 3, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            prices[i] = i == priceZeroIndex ? 0 : 1e18;
        }

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), false)
        );
        // All non-zero prices are equal, no deviation, return first non-zero (min)
        assertEq(price, 1e18, "should ignore zero price");
    }

    // ========== FUZZ TESTS: ZERO PRICE WITH DEVIATION ========== //

    function test_whenOnePriceZero_whenDeviating_fuzz(
        uint8 priceZeroIndex_,
        uint256 basePrice_,
        uint256 deviationAmount_
    ) public view {
        uint16 deviationBps = 100; // 1%
        // Zero price index between 0 and 9 (for 10 element array)
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 0, 9));
        // Base price between 0.5e18 and 1.5e18
        uint256 basePrice = bound(basePrice_, 0.5e18, 1.5e18);
        // Deviation amount between 2% and 100% of base price (ensures deviation detected)
        uint256 deviationAmount = bound(deviationAmount_, basePrice / 50, basePrice);

        uint256[] memory prices = new uint256[](10);
        uint256 nonZeroCount = 0;

        // Track whether we've assigned the deviating price yet
        bool deviatingPriceAssigned = false;

        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else if (!deviatingPriceAssigned) {
                // First non-zero price gets the deviation
                prices[i] = basePrice + deviationAmount;
                nonZeroCount++;
                deviatingPriceAssigned = true;
            } else {
                // All other non-zero prices are basePrice
                prices[i] = basePrice;
                nonZeroCount++;
            }
        }

        // 9 non-zero elements: [basePrice x8, basePrice+deviationAmount x1]
        // Sorted: [basePrice, ..., basePrice (8x), basePrice+deviationAmount]
        // Median of 9 elements = 5th element = basePrice
        uint256 expectedMedian = basePrice;

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        assertEq(
            price,
            expectedMedian,
            "should return median of non-zero prices when deviation detected"
        );
    }

    // ========== FUZZ TESTS: FULL DEVIATION RANGE ========== //

    function test_whenNotDeviating_fuzz(uint16 deviationBps_) public view {
        // Prices: 1e18, 1.0001e18, 1.0002e18 (max 0.02% apart = 2 bps)
        // deviationBps > 2 should never detect deviation
        uint16 deviationBps = uint16(bound(deviationBps_, 3, 9999));

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.0001e18;
        prices[2] = 1.0002e18;

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        // No deviation, return first (min) price = 1e18
        assertEq(price, 1e18, "should return first price when deviation too small");
    }

    function test_whenDeviating_fuzz(uint16 deviationBps_) public view {
        // Three prices where extremes deviate from average
        // 1e18, 1.5e18, 2e18 -> average = 1.5e18
        // Deviation of 1e18 from 1.5e18 = 33% = 3333 bps
        // Deviation of 2e18 from 1.5e18 = 33% = 3333 bps
        uint16 deviationBps = uint16(bound(deviationBps_, 1, 3332));

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.5e18;
        prices[2] = 2e18;

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        // Sorted: [1e18, 1.5e18, 2e18], median = 1.5e18
        assertEq(price, 1.5e18, "should return median when deviation above threshold");
    }
}
