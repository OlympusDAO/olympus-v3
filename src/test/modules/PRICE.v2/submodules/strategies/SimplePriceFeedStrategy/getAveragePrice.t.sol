// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

// Libraries
import {Math} from "libraries/Balancer/math/Math.sol";

/// @title Tests for getAveragePrice function
/// @notice Tests the average price aggregation strategy
contract SimplePriceFeedStrategyGetAveragePriceTest is SimplePriceFeedStrategyBase {
    using Math for uint256;

    // =========  TESTS ========= //

    function test_getAveragePrice_revertsOnArrayLengthInvalid(uint8 len_) public {
        uint8 len = uint8(bound(len_, 0, 1));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(len, 2);

        strategy.getAveragePrice(prices, "");
    }

    function test_getAveragePrice_empty_fuzz(uint8 len_) public view {
        uint8 len = uint8(bound(len_, 2, 10));
        uint256[] memory prices = new uint256[](len);

        uint256 returnedPrice = strategy.getAveragePrice(prices, "");
        assertEq(returnedPrice, 0);
    }

    function test_getAveragePrice_priceZeroFuzz(uint8 priceZeroIndex_) public view {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 2, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else {
                prices[i] = 1e18;
            }
        }

        uint256 averagePrice = strategy.getAveragePrice(prices, "");

        // The average price will be 1e18, which means the zero price will be ignored
        assertEq(averagePrice, 1e18);
    }

    function test_getAveragePrice_lengthEven() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 2e18;

        uint256 price = strategy.getAveragePrice(prices, "");

        assertEq(price, 15 * 10 ** 17);
    }

    function test_getAveragePrice_lengthOdd() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 2e18;
        prices[2] = 3e18;

        uint256 price = strategy.getAveragePrice(prices, "");

        assertEq(price, 2e18);
    }

    function test_getAveragePrice_lengthEven_priceZero() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1e18;
        prices[1] = 2e18;
        prices[2] = 0;
        prices[3] = 3e18;

        uint256 price = strategy.getAveragePrice(prices, "");

        // Ignores the zero price
        assertEq(price, 2e18);
    }
}
