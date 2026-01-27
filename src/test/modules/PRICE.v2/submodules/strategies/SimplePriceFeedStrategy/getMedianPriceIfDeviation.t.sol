// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

// Libraries
import {Math} from "libraries/Balancer/math/Math.sol";
import {QuickSort} from "libraries/QuickSort.sol";

/// @title Tests for getMedianPriceIfDeviation function
/// @notice Tests the deviation-based median price strategy
contract SimplePriceFeedStrategyGetMedianPriceIfDeviationTest is SimplePriceFeedStrategyBase {
    using Math for uint256;
    using QuickSort for uint256[];

    // =========  TESTS ========= //

    function test_getMedianPriceIfDeviation_revertsOnArrayLengthInvalid(uint8 len_) public {
        uint8 len = uint8(bound(len_, 0, 2));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(len, 3);

        strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(100));
    }

    function test_getMedianPriceIfDeviation_priceZero_indexFuzz(uint8 priceZeroIndex_) public view {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 2, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else {
                prices[i] = 1e18;
            }
        }

        uint256 medianPrice = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(100)
        );

        // Ignores the zero price
        assertEq(medianPrice, 1e18);
    }

    function test_getMedianPriceIfDeviation_empty_fuzz(uint8 len_) public view {
        uint8 len = uint8(bound(len_, 3, 10));
        uint256[] memory prices = new uint256[](len);

        uint256 medianPrice = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(100)
        );

        // Handles the zero price
        assertEq(medianPrice, 0);
    }

    function test_getMedianPriceIfDeviation_fourItems() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;
        prices[3] = 0.99 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.001 * 1e18) / 2); // Average of the middle two
    }

    function test_getMedianPriceIfDeviation_fiveItems_priceZero() public view {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;
        prices[3] = 1.001 * 1e18;
        prices[4] = 0.99 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(price, (1 * 1e18 + 1.001 * 1e18) / 2); // Average of the middle two
    }

    function test_getMedianPriceIfDeviation_threeItems_fuzz(
        uint256 priceOne_,
        uint256 priceTwo_,
        uint256 priceThree_
    ) public view {
        uint256 deviationBps = 100; // 1%

        uint256 priceOne = bound(priceOne_, 0.001 * 1e18, 2 * 1e18);
        uint256 priceTwo = bound(priceTwo_, 0.001 * 1e18, 2 * 1e18);
        uint256 priceThree = bound(priceThree_, 0.001 * 1e18, 2 * 1e18);

        uint256[] memory prices = new uint256[](3);
        prices[0] = priceOne;
        prices[1] = priceTwo;
        prices[2] = priceThree;

        uint256 price = strategy.getMedianPriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps)
        );

        uint256 expectedPrice;
        {
            uint256 averagePrice = (priceOne + priceTwo + priceThree) / 3;
            uint256 minPrice = priceOne.min(priceTwo).min(priceThree);
            uint256 maxPrice = priceOne.max(priceTwo).max(priceThree);

            // Check if the minPrice or maxPrice deviate sufficiently from the averagePrice
            bool minPriceDeviation = _isDeviating(minPrice, averagePrice, deviationBps);
            bool maxPriceDeviation = _isDeviating(maxPrice, averagePrice, deviationBps);

            // NOTE: this occurs after the `getMedianPriceIfDeviation` function call, as it modifies the prices array
            uint256[] memory sortedPrices = prices.sort();
            uint256 medianPrice = sortedPrices[1];

            // Expected price is the median if there is a minPriceDeviation or maxPriceDeviation, otherwise the first price value
            expectedPrice = minPriceDeviation || maxPriceDeviation ? medianPrice : priceOne;
        }

        assertEq(price, expectedPrice);
    }

    function test_getMedianPriceIfDeviation_threeItems_deviationIndexOne() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(100));
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianPriceIfDeviation_threeItems_priceZero_deviation() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 0;
        prices[2] = 1.2 * 1e18; // > 1% deviation

        uint256 price = strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.2 * 1e18) / 2); // < 3 non-zero items and deviating, returns average
    }

    function test_getMedianPriceIfDeviation_threeItems_priceZero() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 0;
        prices[2] = 1.001 * 1e18; // < 1% deviation

        uint256 price = strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(100));
        assertEq(price, 1e18); // < 3 non-zero items, returns first non-zero price
    }

    function test_getMedianPriceIfDeviation_threeItems_priceZero_indexZero() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1 * 1e18;
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(100));
        assertEq(price, 1e18); // < 3 non-zero items, returns first non-zero price
    }

    function test_getMedianPriceIfDeviation_fourItems_deviationIndexOne_priceZero() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;
        prices[3] = 1.001 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianPriceIfDeviation_threeItems_deviationIndexTwo() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.2 * 1e18; // > 1% deviation

        uint256 price = strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(100));
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianPriceIfDeviation_revertsOnMissingParams() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.002 * 1e18;

        _expectRevertParams("");

        strategy.getMedianPriceIfDeviation(prices, "");
    }

    function test_getMedianPriceIfDeviation_revertsOnMissingParamsDeviationBpsEmpty() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.002 * 1e18;

        _expectRevertParams(abi.encode(""));

        strategy.getMedianPriceIfDeviation(prices, abi.encode(""));
    }

    function test_getMedianPriceIfDeviation_paramsDeviationBps_fuzz(uint256 deviationBps_) public {
        uint256 deviationBps = bound(deviationBps_, DEVIATION_MIN, DEVIATION_MAX * 2);

        bool isDeviationInvalid = deviationBps <= DEVIATION_MIN || deviationBps >= DEVIATION_MAX;

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.002 * 1e18;

        if (isDeviationInvalid) _expectRevertParams(_encodeDeviationParams(deviationBps));

        strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(deviationBps));
    }

    function test_getMedianPriceIfDeviation_withoutDeviation() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18; // < 1% deviation
        prices[2] = 1.002 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, _encodeDeviationParams(100));
        // No deviation, so returns the first price
        assertEq(price, 1 * 1e18);
    }
}
