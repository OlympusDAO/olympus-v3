// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

// Libraries
import {Math} from "libraries/Balancer/math/Math.sol";
import {QuickSort} from "libraries/QuickSort.sol";

/// @title Tests for getMedianPrice function
/// @notice Tests the median price aggregation strategy
contract SimplePriceFeedStrategyGetMedianPriceTest is SimplePriceFeedStrategyBase {
    using Math for uint256;
    using QuickSort for uint256[];

    // =========  TESTS ========= //

    function test_getMedianPrice_priceZero_indexFuzz(uint8 priceZeroIndex_) public view {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 0, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else {
                prices[i] = 1e18;
            }
        }

        uint256 medianPrice = strategy.getMedianPrice(prices, "");

        // The median price will be 1e18, which means the zero price will be ignored
        assertEq(medianPrice, 1e18);
    }

    function test_getMedianPrice_revertsOnArrayLengthInvalid(uint8 len_) public {
        uint8 len = uint8(bound(len_, 0, 2));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(len, 3);
        strategy.getMedianPrice(prices, "");
    }

    function test_getMedianPrice_empty_fuzz(uint8 len_) public view {
        uint8 len = uint8(bound(len_, 3, 10));
        uint256[] memory prices = new uint256[](len);

        uint256 returnedPrice = strategy.getMedianPrice(prices, "");
        assertEq(returnedPrice, 0);
    }

    function test_getMedianPrice_unsorted() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 3 * 1e18;
        prices[1] = 1 * 1e18;
        prices[2] = 1.2 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");
        assertEq(price, 1.2 * 1e18);
    }

    function test_getMedianPrice_unsorted_priceZero() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 3 * 1e18;
        prices[1] = 1 * 1e18;
        prices[2] = 0;
        prices[3] = 1.2 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price
        assertEq(price, 1.2 * 1e18);
    }

    function test_getMedianPrice_arrayLengthValid_priceDoubleZero() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 0;
        prices[2] = 0;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price
        assertEq(price, 1e18);
    }

    function test_getMedianPrice_arrayLengthValid_priceSingleZero() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18;
        prices[2] = 0;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price and returns the average of the non-zero prices
        assertEq(price, (1 * 1e18 + 2 * 1e18) / 2);
    }

    function test_getMedianPrice_arrayLengthValid_priceSingleZero_indexZero() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1 * 1e18;
        prices[2] = 2 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price and returns the average of the non-zero prices
        assertEq(price, (1 * 1e18 + 2 * 1e18) / 2);
    }

    function test_getMedianPrice_lengthOdd() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18;
        prices[2] = 3 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");
        assertEq(price, 1.2 * 1e18);
    }

    function test_getMedianPrice_lengthOdd_priceZero() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18;
        prices[2] = 0;
        prices[3] = 3 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price
        assertEq(price, 1.2 * 1e18);
    }

    function test_getMedianPrice_lengthEven() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 4 * 1e18;
        prices[1] = 2 * 1e18;
        prices[2] = 1 * 1e18;
        prices[3] = 3 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");
        assertEq(price, (2 * 1e18 + 3 * 1e18) / 2);
    }

    function test_getMedianPrice_lengthEven_priceZero() public view {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 4 * 1e18;
        prices[1] = 2 * 1e18;
        prices[2] = 1 * 1e18;
        prices[3] = 0;
        prices[4] = 3 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price
        assertEq(price, (2 * 1e18 + 3 * 1e18) / 2);
    }
}
