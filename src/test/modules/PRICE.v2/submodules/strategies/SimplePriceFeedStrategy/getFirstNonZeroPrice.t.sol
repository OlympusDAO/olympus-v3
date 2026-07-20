// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

/// @title Tests for getFirstNonZeroPrice function
/// @notice Tests the first non-zero price strategy
contract SimplePriceFeedStrategyGetFirstNonZeroPriceTest is SimplePriceFeedStrategyBase {
    // =========  TESTS ========= //

    function test_getFirstNonZeroPrice_revertsOnArrayLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        _expectRevertPriceCount(0, 1);

        strategy.getFirstNonZeroPrice(prices, "");
    }

    function test_getFirstNonZeroPrice_pricesInvalid(uint8 len_) public view {
        uint8 len = uint8(bound(len_, 1, 10));

        uint256[] memory prices = new uint256[](len);
        for (uint8 i; i < len; i++) {
            prices[i] = 0;
        }

        uint256 returnedPrice = strategy.getFirstNonZeroPrice(prices, "");
        assertEq(returnedPrice, 0);
    }

    function test_getFirstNonZeroPrice_success() public view {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1e18;

        uint256 price = strategy.getFirstNonZeroPrice(prices, "");

        assertEq(price, 1e18);
    }

    function test_getFirstNonZeroPrice_arrayLengthGreaterThanTwo_fuzz(uint8 len) public view {
        vm.assume(len > 2 && len <= 10);
        uint256[] memory prices = new uint256[](len);
        for (uint8 i; i < len; i++) {
            prices[i] = 1e18;
        }

        uint256 price = strategy.getFirstNonZeroPrice(prices, "");

        assertEq(price, 1e18);
    }

    function test_getFirstNonZeroPrice_validFirstPrice() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 11e18;
        prices[1] = 10e18;

        uint256 price = strategy.getFirstNonZeroPrice(prices, _encodeDeviationParams(100));
        assertEq(price, 11e18);
    }

    function test_getFirstNonZeroPrice_invalidFirstPrice() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0;
        prices[1] = 10e18;

        uint256 price = strategy.getFirstNonZeroPrice(prices, _encodeDeviationParams(100));
        assertEq(price, 10e18);
    }

    function test_getFirstNonZeroPrice_invalidSecondPrice() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 11e18;
        prices[1] = 0;

        uint256 price = strategy.getFirstNonZeroPrice(prices, _encodeDeviationParams(100));
        assertEq(price, 11e18);
    }

    function test_getFirstNonZeroPrice_fuzz(uint256 firstPrice_, uint256 secondPrice_) public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = firstPrice_;
        prices[1] = secondPrice_;

        uint256 price = strategy.getFirstNonZeroPrice(prices, _encodeDeviationParams(100));
        if (firstPrice_ == 0) {
            assertEq(price, secondPrice_);
        } else {
            assertEq(price, firstPrice_);
        }
    }
}
