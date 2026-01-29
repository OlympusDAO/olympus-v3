// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

/// @title Tests for getAveragePriceIfDeviation function
/// @notice Tests the deviation-based average price strategy
contract SimplePriceFeedStrategyGetAveragePriceIfDeviationTest is SimplePriceFeedStrategyBase {
    // =========  TESTS ========= //

    // ========== CONFIGURATION ERRORS ========== //
    // when input array length is less than 2
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
        uint8 len = uint8(bound(len_, 0, 1));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(len, 2);
        strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(uint16(100), false));
    }

    function test_whenEmptyParams_reverts() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 2e18;

        _expectRevertParams("");
        strategy.getAveragePriceIfDeviation(prices, "");
    }

    function test_whenInvalidParamsLength_reverts() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 2e18;

        bytes memory invalidParams = abi.encode(uint256(123)); // 32 bytes
        _expectRevertParams(invalidParams);
        strategy.getAveragePriceIfDeviation(prices, invalidParams);
    }

    function test_whenDeviationBpsZero_reverts() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 2e18;

        _expectRevertParams(_encodeDeviationParams(0, false));
        strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(0, false));
    }

    function test_whenDeviationBpsTooLarge_reverts(uint16 deviationBps_) public {
        uint16 deviationBps = uint16(bound(deviationBps_, DEVIATION_MAX + 1, 65_535));

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.001e18;
        prices[2] = 1.002e18;

        bytes memory params = _encodeDeviationParams(deviationBps, false);
        _expectRevertParams(params);
        strategy.getAveragePriceIfDeviation(prices, params);
    }

    // ========== ALL PRICES ZERO ========== //
    // when all prices are zero
    //   [X] it reverts

    function test_whenAllPricesZero_reverts(uint8 len_) public {
        uint8 len = uint8(bound(len_, 2, 10));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(0, 2);
        strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(uint16(100), false));
    }

    // ========== ONE NON-ZERO PRICE ========== //
    // when one non-zero price
    //   when strict mode is enabled
    //     [X] it reverts
    //   when strict mode is disabled
    //     [X] it returns that price

    function test_whenOneNonZeroPrice_strictMode_reverts(uint8 arrayLen_) public {
        uint8 arrayLen = uint8(bound(arrayLen_, 2, 10));
        uint256[] memory prices = new uint256[](arrayLen);
        prices[arrayLen - 1] = 1.5e18;

        _expectRevertPriceCount(1, 2);
        strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(uint16(100), true));
    }

    function test_whenOneNonZeroPrice_bestEffortMode(uint8 arrayLen_) public view {
        uint8 arrayLen = uint8(bound(arrayLen_, 2, 10));
        uint256[] memory prices = new uint256[](arrayLen);
        prices[arrayLen - 1] = 1.5e18;

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), false)
        );
        assertEq(price, 1.5e18, "should return the single non-zero price");
    }

    // ========== TWO NON-ZERO PRICES ========== //
    // when there are two non-zero prices
    //   when two prices deviate
    //     [X] it returns the average
    //   when two prices do not deviate
    //     [X] it returns the first price

    function test_whenTwoNonZeroPrices_whenDeviating() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 2e18; // 100% deviation

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), false) // 1% threshold
        );
        // average = (1e18 + 2e18) / 2 = 1.5e18
        assertEq(price, 1.5e18, "should return average when prices deviate");
    }

    function test_whenTwoNonZeroPrices_whenNotDeviating() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 1.001e18; // 0.1% deviation

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), false) // 1% threshold
        );
        assertEq(price, 1e18, "should return first price when no deviation");
    }

    // ========== THREE+ NON-ZERO PRICES WITH DEVIATION ========== //
    // when min price deviates from average
    //   [X] it returns the average
    // when max price deviates from average
    //   [X] it returns the average
    // when no price deviates
    //   [X] it returns the first non-zero price

    function test_whenThreeNonZeroPrices_whenMinDeviating() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.2e18; // 20% deviation from average
        prices[2] = 1.001e18;

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), false) // 1% threshold
        );
        // average = (1 + 1.2 + 1.001) / 3 = 1.067e18
        uint256 expectedAverage = (1e18 + 1.2e18 + 1.001e18) / 3;
        assertEq(price, expectedAverage, "should return average when min deviates");
    }

    function test_whenThreeNonZeroPrices_whenMaxDeviating() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.001e18;
        prices[2] = 1.2e18; // 20% deviation from average

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), false) // 1% threshold
        );
        // average = (1 + 1.001 + 1.2) / 3 = 1.067e18
        uint256 expectedAverage = (1e18 + 1.001e18 + 1.2e18) / 3;
        assertEq(price, expectedAverage, "should return average when max deviates");
    }

    function test_whenThreeNonZeroPrices_whenNoDeviating() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.001e18; // 0.1% deviation < 1% threshold
        prices[2] = 1.002e18; // 0.2% deviation < 1% threshold

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), false) // 1% threshold
        );
        assertEq(price, 1e18, "should return first price when no deviation");
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

        uint256 expectedAverage = (basePrice * 2 + (basePrice + deviationAmount)) / 3;

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        assertEq(price, expectedAverage, "should return average when deviation detected");
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
        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        assertEq(price, basePrice, "should return first price when no deviation");
    }

    function test_whenOnePriceZero_whenNotDeviating_fuzz(uint8 priceZeroIndex_) public view {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 2, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            prices[i] = i == priceZeroIndex ? 0 : 1e18;
        }

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(uint16(100), false)
        );
        // All non-zero prices are equal, no deviation, return first non-zero
        assertEq(price, 1e18, "should ignore zero price");
    }

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
        uint256 nonZeroSum = 0;

        // Track whether we've assigned the deviating price yet
        bool deviatingPriceAssigned = false;

        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else if (!deviatingPriceAssigned) {
                // First non-zero price gets the deviation
                prices[i] = basePrice + deviationAmount;
                nonZeroSum += basePrice + deviationAmount;
                nonZeroCount++;
                deviatingPriceAssigned = true;
            } else {
                // All other non-zero prices are basePrice
                prices[i] = basePrice;
                nonZeroSum += basePrice;
                nonZeroCount++;
            }
        }

        uint256 expectedAverage = nonZeroSum / nonZeroCount;

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        assertEq(
            price,
            expectedAverage,
            "should return average of non-zero prices when deviation detected"
        );
    }

    // ========== FUZZ TESTS: FULL DEVIATION RANGE ========== //

    function test_whenNotDeviating_fuzz(uint16 deviationBps_) public view {
        // Prices: 1e18, 1.0001e18 (0.01% apart = 1 bps)
        // deviationBps > 1 should never detect deviation
        uint16 deviationBps = uint16(bound(deviationBps_, 2, 9999));

        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 1.0001e18;

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        // No deviation, return first (min) price = 1e18
        assertEq(price, 1e18, "should return first price when deviation too small");
    }

    function test_whenDeviating_fuzz(uint16 deviationBps_) public view {
        // Three prices where extremes deviate by ~50% from average
        // 1e18, 1.5e18, 2e18 -> average = 1.5e18
        // Deviation of 1e18 from 1.5e18 = 33% = 3333 bps
        // Deviation of 2e18 from 1.5e18 = 33% = 3333 bps
        uint16 deviationBps = uint16(bound(deviationBps_, 1, 3332));

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.5e18;
        prices[2] = 2e18;

        uint256 expectedAverage = (1e18 + 1.5e18 + 2e18) / 3;

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        assertEq(price, expectedAverage, "should return average when deviation above threshold");
    }
}
