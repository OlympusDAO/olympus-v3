// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

/// @title Tests for getMedianPriceExcludingDeviations function
/// @notice Tests the deviation-based median price strategy that excludes outliers
contract SimplePriceFeedStrategyGetMedianPriceExcludingDeviationsTest is
    SimplePriceFeedStrategyBase
{
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
        strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(100), false)
        );
    }

    function test_whenEmptyParams_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.001e18;
        prices[2] = 1.002e18;

        _expectRevertParams("");
        strategy.getMedianPriceExcludingDeviations(prices, "");
    }

    function test_whenInvalidParamsLength_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.001e18;
        prices[2] = 1.002e18;

        bytes memory invalidParams = abi.encode(uint256(123)); // 32 bytes
        _expectRevertParams(invalidParams);
        strategy.getMedianPriceExcludingDeviations(prices, invalidParams);
    }

    function test_whenDeviationBpsZero_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.001e18;
        prices[2] = 1.002e18;

        _expectRevertParams(_encodeDeviationParams(uint16(0), false));
        strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(0), false)
        );
    }

    function test_whenDeviationBpsTooLarge_reverts(uint16 deviationBps_) public {
        uint16 deviationBps = uint16(bound(deviationBps_, DEVIATION_MAX + 1, 65_535));

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.001e18;
        prices[2] = 1.002e18;

        bytes memory params = _encodeDeviationParams(deviationBps, false);
        _expectRevertParams(params);
        strategy.getMedianPriceExcludingDeviations(prices, params);
    }

    // ========== ALL PRICES ZERO ========== //
    // when all prices are zero
    //   [X] it reverts

    function test_whenAllPricesZero_reverts(uint8 len_) public {
        uint8 len = uint8(bound(len_, 3, 10));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(0, 3);
        strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(100), false)
        );
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
        strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(100), true)
        );
    }

    function test_whenOneNonZeroPrice_bestEffortMode(uint8 arrayLen_) public view {
        uint8 arrayLen = uint8(bound(arrayLen_, 3, 10));
        uint256[] memory prices = new uint256[](arrayLen);
        prices[arrayLen - 1] = 1.5e18;

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(100), false)
        );
        assertEq(price, 1.5e18, "should return the single non-zero price");
    }

    // ========== TWO NON-ZERO PRICES ========== //
    // when there are two non-zero prices
    //   when strict mode is enabled
    //     [X] it reverts
    //   when best effort mode
    //     when neither deviates
    //       [X] it returns the average
    //     when both deviate
    //       [X] it reverts
    //
    // Note: With 2 prices, both have the same deviation from their average (equidistant).
    // So either both deviate or neither does - "one deviates" is impossible.

    function test_whenTwoNonZeroPrices_whenStrictMode_reverts(
        uint256 priceOne_,
        uint256 priceTwo_
    ) public {
        priceOne_ = bound(priceOne_, 1e18, 1.5e18);
        priceTwo_ = bound(priceTwo_, 1e18, 1.5e18);

        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = priceOne_;
        prices[2] = priceTwo_;

        _expectRevertPriceCount(2, 3);
        strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(100), true)
        );
    }

    function test_whenTwoNonZeroPrices_whenBestEffortMode_whenNotDeviating() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 1.01e18; // ~0.5% deviation from avg of 1.005e18

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(200), false)
        );
        // Neither deviates at 2% threshold, return avg
        assertEq(
            price,
            (1e18 + 1.01e18) / 2,
            "should return average when two prices don't deviate"
        );
    }

    function test_whenTwoNonZeroPrices_whenBestEffortMode_whenDeviating_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 1.01e18; // ~0.5% deviation from avg of 1.005e18

        // Will revert because both prices deviate from the average, leaving no prices to return
        _expectRevertPriceCount(0, 2);
        strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(40), false)
        );
    }

    // ========== THREE+ NON-ZERO PRICES WITH DEVIATION ========== //
    // when there are three non-zero prices
    //   when no prices deviate
    //     [X] it returns the median
    //   when one price deviates
    //     when strict mode is enabled
    //       [X] it reverts
    //     when strict mode is disabled
    //       [X] it returns the average of the remaining prices
    //   when two prices deviate
    //     when strict mode is enabled
    //       [X] it reverts
    //     when strict mode is disabled
    //       [X] it returns the remaining price
    //
    // Note: "all prices deviate" is impossible since median has 0 deviation from itself.

    function test_whenThreeNonZeroPrices_whenNotDeviating(uint8 mode_) public view {
        mode_ = uint8(bound(mode_, 0, 1));
        bool strictMode = mode_ == 0;

        uint256[] memory prices = new uint256[](4);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 1.001e18;
        prices[3] = 1.002e18; // All within 1%

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(100), strictMode)
        );
        // median of [1e18, 1.001e18, 1.002e18] = 1.001e18
        assertEq(price, 1.001e18, "should return median when no deviation");
    }

    function test_whenThreeNonZeroPrices_whenMinDeviates_bestEffortMode() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 0;
        prices[1] = 1e18; // Will deviate from median of 1.101e18
        prices[2] = 1.1e18;
        prices[3] = 1.101e18;

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(50), false)
        );
        // median = 1.1e18, 1e18 deviates (~9%), remaining [1.1e18, 1.101e18], average = 1.1005e18
        assertEq(price, (1.1e18 + 1.101e18) / 2, "should return average of remaining prices");
    }

    function test_whenThreeNonZeroPrices_whenMinDeviates_strictMode_reverts() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 0;
        prices[1] = 1e18; // Will deviate from median of 1.101e18
        prices[2] = 1.1e18;
        prices[3] = 1.101e18;

        // Will revert as there are only two non-deviating prices, which isn't enough for a median
        _expectRevertPriceCount(2, 3);
        strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(50), true)
        );
    }

    function test_whenThreeNonZeroPrices_whenMaxDeviates_bestEffortMode() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 0;
        prices[1] = 1.1e18;
        prices[2] = 1.101e18;
        prices[3] = 1.2e18; // Will deviate from median of 1.101e18

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(50), false)
        );
        // median = 1.101e18, 1.2e18 deviates (~9%), remaining [1.1e18, 1.101e18], average = 1.1005e18
        assertEq(price, (1.1e18 + 1.101e18) / 2, "should return average of remaining prices");
    }

    function test_whenThreeNonZeroPrices_whenTwoDeviating_bestEffortMode() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 0;
        prices[1] = 1e18; // Will deviate from median of 1.1e18
        prices[2] = 1.1e18;
        prices[3] = 1.2e18; // Will deviate from median of 1.1e18

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(50), false)
        );
        // median = 1.1e18, extremes deviate (>9%), middle remains
        assertEq(price, 1.1e18, "should return middle price when extremes deviate");
    }

    function test_whenThreeNonZeroPrices_whenTwoDeviating_strictMode_reverts() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 1.5e18; // Median, won't deviate from itself
        prices[3] = 2e18; // Will deviate

        _expectRevertPriceCount(1, 3);
        strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(1000), true)
        );
    }

    // ========== FOUR+ PRICES ========== //

    // when there are four non-zero prices
    //   when one price deviates
    //     when strict mode is enabled
    //       [X] it returns the median of the remaining prices
    //     when strict mode is disabled
    //       [X] it returns the median of the remaining prices
    //   when two prices deviate
    //     when strict mode is enabled
    //       [X] it reverts
    //     when strict mode is disabled
    //       [X] it returns the average of the remaining prices

    function test_whenFourPrices_whenOneDeviating(uint8 mode_) public view {
        mode_ = uint8(bound(mode_, 0, 1));
        bool strictMode = mode_ == 0;

        uint256[] memory prices = new uint256[](5);
        prices[0] = 0;
        prices[1] = 1e18;
        prices[2] = 1.05e18;
        prices[3] = 1.1e18;
        prices[4] = 1.12e18; // Will deviate from median of 1.075e18 at 5%

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(500), strictMode) // 5% threshold
        );
        // median = 1.075e18, 1e18 deviates (~7%), remaining [1.05e18, 1.1e18, 1.12e18]
        // median of 3 remaining = 1.1e18
        assertEq(price, 1.1e18, "should return median when one price deviates");
    }

    function test_whenFourPrices_whenTwoDeviating_bestEffortMode() public view {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 0;
        prices[1] = 1e18; // Will deviate from median 1.075e18
        prices[2] = 1.05e18;
        prices[3] = 1.1e18;
        prices[4] = 1.25e18; // Will deviate from median 1.075e18

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(500), false) // 5% threshold
        );
        // median = 1.075e18, 1e18 (~7%) and 1.25e18 (~16%) deviate, remaining [1.05e18, 1.1e18]
        // median of 2 = average = 1.075e18
        assertEq(price, (1.05e18 + 1.1e18) / 2, "should return average of remaining prices");
    }

    function test_whenFourPrices_whenTwoDeviating_strictMode_reverts() public {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 0;
        prices[1] = 1e18; // Will deviate from median 1.075e18
        prices[2] = 1.05e18;
        prices[3] = 1.1e18;
        prices[4] = 1.25e18; // Will deviate from median 1.075e18

        _expectRevertPriceCount(2, 3);
        strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(uint16(500), true) // 5% threshold
        );
    }

    // ========== FUZZ TESTS ========== //

    function test_whenThreePrices_noDeviation_fuzz(
        uint256 basePrice_,
        uint256 smallVariance_
    ) public view {
        uint16 deviationBps = 100; // 1%
        uint256 basePrice = bound(basePrice_, 0.5e18, 1.5e18);
        uint256 smallVariance = bound(smallVariance_, 0, basePrice / 200);

        uint256[] memory prices = new uint256[](3);
        prices[0] = basePrice;
        prices[1] = basePrice + smallVariance;
        prices[2] = basePrice + smallVariance / 2;

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        // All prices within threshold, median should be middle value
        uint256[] memory sortedPrices = new uint256[](3);
        sortedPrices[0] = basePrice;
        sortedPrices[1] = basePrice + smallVariance / 2;
        sortedPrices[2] = basePrice + smallVariance;
        uint256 expectedMedian = _getMedianPrice(sortedPrices, 3);
        assertEq(price, expectedMedian, "should return median when no deviation");
    }

    function test_whenFourPrices_oneDeviation_fuzz(
        uint256 basePrice_,
        uint256 deviationAmount_
    ) public view {
        uint16 deviationBps = 100; // 1%
        uint256 basePrice = bound(basePrice_, 0.5e18, 1.5e18);
        uint256 deviationAmount = bound(deviationAmount_, basePrice / 50, basePrice);

        uint256[] memory prices = new uint256[](4);
        prices[0] = basePrice;
        prices[1] = basePrice + deviationAmount; // Will deviate from median
        prices[2] = basePrice + basePrice / 400; // Small variance
        prices[3] = basePrice + basePrice / 200; // Small variance

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        // Deviating price excluded, 3 remain, return median of 3
        // Sorted: [basePrice, basePrice + 1/400, basePrice + 1/200]
        // Median = middle value = basePrice + 1/400
        assertEq(
            price,
            basePrice + basePrice / 400,
            "should return median after excluding deviation"
        );
    }

    function test_whenOnePriceZero_withDeviation_fuzz(
        uint8 priceZeroIndex_,
        uint256 basePrice_,
        uint256 deviationAmount_
    ) public view {
        uint16 deviationBps = 100; // 1%
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 0, 9));
        uint256 basePrice = bound(basePrice_, 0.5e18, 1.5e18);
        uint256 deviationAmount = bound(deviationAmount_, basePrice / 50, basePrice);

        uint256[] memory prices = new uint256[](10);
        bool deviatingAssigned = false;
        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else if (!deviatingAssigned) {
                prices[i] = basePrice + deviationAmount;
                deviatingAssigned = true;
            } else {
                prices[i] = basePrice;
            }
        }

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        // 9 non-zero prices with 1 deviating from median, 8 remain
        // Sorted: [basePrice x8, basePrice+deviationAmount]
        // Median of 8 = avg of 4th and 5th = basePrice
        assertEq(price, basePrice, "should return median after excluding deviation and zero");
    }

    function test_whenThreePrices_whenDeviating_deviationBpsFuzz(uint16 deviationBps_) public view {
        // Three prices where one deviates significantly
        // 1e18, 1.01e18, 1.5e18 -> median = 1.01e18
        // 1e18 deviation from median ~ 99 bps
        // 1.5e18 deviation from median ~ 4852 bps
        // Use deviationBps in range [100, 4800] to exclude only 1.5e18
        uint16 deviationBps = uint16(bound(deviationBps_, 100, 4800));

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.01e18;
        prices[2] = 1.5e18;

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        // 1.5e18 excluded, remaining [1e18, 1.01e18], median = avg = 1.005e18
        assertEq(price, (1e18 + 1.01e18) / 2, "should return median of non-deviating prices");
    }

    function test_whenThreePrices_whenNotDeviating_deviationBpsFuzz(
        uint16 deviationBps_
    ) public view {
        // Three prices where none deviate
        // 1e18, 1.01e18, 1.02e18 -> median = 1.01e18
        // Max deviation ~1% = 100 bps
        uint16 deviationBps = uint16(bound(deviationBps_, 101, 9999));

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 1.01e18;
        prices[2] = 1.02e18;

        uint256 price = strategy.getMedianPriceExcludingDeviations(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        // None excluded, median = 1.01e18
        assertEq(price, 1.01e18, "should return median when no deviation");
    }

    // ========== HELPER FUNCTION ========== //

    function _getMedianPrice(
        uint256[] memory prices,
        uint256 count
    ) internal pure returns (uint256) {
        if (count % 2 == 0) {
            return (prices[count / 2 - 1] + prices[count / 2]) / 2;
        }
        return prices[count / 2];
    }
}
