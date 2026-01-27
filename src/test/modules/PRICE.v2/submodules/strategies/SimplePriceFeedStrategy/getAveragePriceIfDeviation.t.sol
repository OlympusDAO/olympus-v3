// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

// Libraries
import {Math} from "libraries/Balancer/math/Math.sol";

/// @title Tests for getAveragePriceIfDeviation function
/// @notice Tests the deviation-based average price strategy
contract SimplePriceFeedStrategyGetAveragePriceIfDeviationTest is SimplePriceFeedStrategyBase {
    using Math for uint256;

    // =========  TESTS ========= //

    function test_getAveragePriceIfDeviation_revertsOnArrayLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        _expectRevertPriceCount(0, 2);

        strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(100));
    }

    function test_getAveragePriceIfDeviation_revertsOnArrayLengthOne() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1 * 1e18;

        _expectRevertPriceCount(1, 2);

        strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(100));
    }

    function test_getAveragePriceIfDeviation_empty_fuzz(uint8 len_) public view {
        uint8 len = uint8(bound(len_, 2, 10));

        uint256[] memory prices = new uint256[](len);

        uint256 returnedPrice = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(100)
        );
        assertEq(returnedPrice, 0);
    }

    function test_getAveragePriceIfDeviation_arrayLengthTwo_singlePriceZero() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0;
        prices[1] = 1 * 1e18;

        uint256 returnedPrice = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(100)
        );

        // Ignores the zero price
        assertEq(returnedPrice, 1e18);
    }

    function test_getAveragePriceIfDeviation_priceZeroFuzz(uint8 priceZeroIndex_) public view {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 2, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else {
                prices[i] = 1e18;
            }
        }

        uint256 averagePrice = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(100)
        );

        // Ignores the zero price
        assertEq(averagePrice, 1e18);
    }

    function test_getAveragePriceIfDeviation_threeItems_fuzz(
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

        uint256 averagePrice = (priceOne + priceTwo + priceThree) / 3;
        uint256 minPrice = priceOne.min(priceTwo).min(priceThree);
        uint256 maxPrice = priceOne.max(priceTwo).max(priceThree);

        // Check if the minPrice or maxPrice deviate sufficiently from the averagePrice
        bool minPriceDeviation = _isDeviating(minPrice, averagePrice, deviationBps);
        bool maxPriceDeviation = _isDeviating(maxPrice, averagePrice, deviationBps);
        // Expected price is the average if there is a minPriceDeviation or maxPriceDeviation, otherwise the first price value
        uint256 expectedPrice = minPriceDeviation || maxPriceDeviation ? averagePrice : priceOne;

        uint256 price = strategy.getAveragePriceIfDeviation(
            prices,
            _encodeDeviationParams(deviationBps)
        );
        assertEq(price, expectedPrice);
    }

    function test_getAveragePriceIfDeviation_threeItems_deviationIndexOne() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.2 * 1e18 + 1.001 * 1e18) / 3);
    }

    function test_getAveragePriceIfDeviation_threeItems_priceZeroTwice() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;

        uint256 price = strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(100));

        // Returns first non-zero price
        assertEq(price, 1.2 * 1e18);
    }

    function test_getAveragePriceIfDeviation_threeItems_priceZero() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;

        uint256 price = strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(100));

        // Returns the average of the non-zero prices
        assertEq(price, (1 * 1e18 + 1.2 * 1e18) / 2);
    }

    function test_getAveragePriceIfDeviation_fourItems_priceZero() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;
        prices[3] = 1.001 * 1e18;

        uint256 price = strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(price, (1 * 1e18 + 1.2 * 1e18 + 1.001 * 1e18) / 3);
    }

    function test_getAveragePriceIfDeviation_threeItems_deviationIndexTwo() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.2 * 1e18; // > 1% deviation

        uint256 price = strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.001 * 1e18 + 1.2 * 1e18) / 3);
    }

    function test_getAveragePriceIfDeviation_twoItems() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18; // > 1% deviation

        uint256 price = strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 2 * 1e18) / 2);
    }

    function test_getAveragePriceIfDeviation_revertsOnMissingParams() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;

        _expectRevertParams("");

        strategy.getAveragePriceIfDeviation(prices, "");
    }

    function test_getAveragePriceIfDeviation_paramsDeviationBps_fuzz(uint256 deviationBps_) public {
        uint256 deviationBps = bound(deviationBps_, DEVIATION_MIN, DEVIATION_MAX * 2);

        bool isDeviationInvalid = deviationBps <= DEVIATION_MIN || deviationBps >= DEVIATION_MAX;

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.002 * 1e18;

        if (isDeviationInvalid) _expectRevertParams(_encodeDeviationParams(deviationBps));

        strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(deviationBps));
    }

    function test_getAveragePriceIfDeviation_revertsOnMissingParamsDeviationBpsEmpty() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;

        _expectRevertParams(abi.encode(""));

        strategy.getAveragePriceIfDeviation(prices, abi.encode(""));
    }

    function test_getAveragePriceIfDeviation_withoutDeviation() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18; // < 1% deviation

        uint256 price = strategy.getAveragePriceIfDeviation(prices, _encodeDeviationParams(100));
        assertEq(price, 1 * 1e18);
    }
}
