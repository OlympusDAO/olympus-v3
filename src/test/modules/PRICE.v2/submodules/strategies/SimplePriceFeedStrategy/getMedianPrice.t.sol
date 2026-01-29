// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

// Libraries
import {QuickSort} from "libraries/QuickSort.sol";

/// @title Tests for getMedianPrice function
/// @notice Tests the median price aggregation strategy
contract SimplePriceFeedStrategyGetMedianPriceTest is SimplePriceFeedStrategyBase {
    using QuickSort for uint256[];

    // =========  TESTS ========= //

    // ========== CONFIGURATION ERRORS ========== //

    function test_whenInvalidArrayLength_reverts(uint8 len_) public {
        uint8 len = uint8(bound(len_, 0, 2));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(len, 3);
        strategy.getMedianPrice(prices, _encodeStrictModeParams(false));
    }

    function test_whenEmptyParams_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 2e18;
        prices[2] = 3e18;

        _expectRevertParams("");
        strategy.getMedianPrice(prices, "");
    }

    function test_whenInvalidParamsLength_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 2e18;
        prices[2] = 3e18;

        bytes memory invalidParams = abi.encode(uint256(123), uint256(456)); // 64 bytes

        _expectRevertParams(invalidParams);
        strategy.getMedianPrice(prices, invalidParams);
    }

    // ========== ALL PRICES ZERO ========== //

    function test_whenAllPricesZero_reverts(uint8 len_) public {
        uint8 len = uint8(bound(len_, 3, 10));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(0, 3);
        strategy.getMedianPrice(prices, _encodeStrictModeParams(false));
    }

    // ========== ONE NON-ZERO PRICE ========== //

    function test_whenOneNonZeroPrice(uint8 arrayLen_) public view {
        uint8 arrayLen = uint8(bound(arrayLen_, 3, 10));
        uint256[] memory prices = new uint256[](arrayLen);
        prices[arrayLen - 1] = 1.5e18;

        uint256 price = strategy.getMedianPrice(prices, _encodeStrictModeParams(false));
        assertEq(price, 1.5e18, "should return the single non-zero price");
    }

    function test_whenOneNonZeroPrice_whenStrictMode_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[2] = 1e18;

        _expectRevertPriceCount(1, 3);
        strategy.getMedianPrice(prices, _encodeStrictModeParams(true));
    }

    // ========== TWO NON-ZERO PRICES ========== //

    function test_whenTwoNonZeroPrices(uint8 arrayLen_) public view {
        uint8 arrayLen = uint8(bound(arrayLen_, 3, 10));
        uint256[] memory prices = new uint256[](arrayLen);
        prices[arrayLen - 2] = 1e18;
        prices[arrayLen - 1] = 2e18;

        // (1e18 + 2e18) / 2 = 1.5e18
        uint256 price = strategy.getMedianPrice(prices, _encodeStrictModeParams(false));
        assertEq(price, 1.5e18, "should return average of two non-zero prices");
    }

    function test_whenTwoNonZeroPrices_whenStrictMode_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[1] = 1e18;
        prices[2] = 2e18;

        _expectRevertPriceCount(2, 3);
        strategy.getMedianPrice(prices, _encodeStrictModeParams(true));
    }

    // ========== THREE+ NON-ZERO PRICES ========== //

    function test_whenThreePricesUnsorted() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 3 * 1e18;
        prices[1] = 1 * 1e18;
        prices[2] = 1.2 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, _encodeStrictModeParams(false));
        assertEq(price, 1.2e18, "should return median of three unsorted prices");
    }

    function test_whenFourPricesUnsorted() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 3 * 1e18;
        prices[1] = 1 * 1e18;
        prices[2] = 0;
        prices[3] = 1.2 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, _encodeStrictModeParams(false));
        assertEq(price, 1.2e18, "should return median of three non-zero prices");
    }

    function test_whenOddLengthArray() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18;
        prices[2] = 3 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, _encodeStrictModeParams(false));
        assertEq(price, 1.2e18, "should return middle price from odd-length array");
    }

    function test_whenOddLengthArray_oneZero() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18;
        prices[2] = 0;
        prices[3] = 3 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, _encodeStrictModeParams(false));
        assertEq(price, 1.2e18, "should return middle price from odd-length array with one zero");
    }

    function test_whenEvenLengthArray() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 4 * 1e18;
        prices[1] = 2 * 1e18;
        prices[2] = 1 * 1e18;
        prices[3] = 3 * 1e18;

        // Average of middle two: (2e18 + 3e18) / 2 = 2.5e18
        uint256 price = strategy.getMedianPrice(prices, _encodeStrictModeParams(false));
        assertEq(price, 2.5e18, "should return average of two middle prices");
    }

    function test_whenEvenLengthArray_oneZero() public view {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 4 * 1e18;
        prices[1] = 2 * 1e18;
        prices[2] = 1 * 1e18;
        prices[3] = 0;
        prices[4] = 3 * 1e18;

        // Average of middle two: (2e18 + 3e18) / 2 = 2.5e18
        uint256 price = strategy.getMedianPrice(prices, _encodeStrictModeParams(false));
        assertEq(price, 2.5e18, "should return average of two middle prices with one zero");
    }

    function test_whenOnePriceZero_outOfTen(uint8 priceZeroIndex_) public view {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 0, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            prices[i] = i == priceZeroIndex ? 0 : 1e18;
        }

        uint256 medianPrice = strategy.getMedianPrice(prices, _encodeStrictModeParams(false));
        assertEq(medianPrice, 1e18, "should return median when one price out of ten is zero");
    }

    // ========== STRICT MODE WITH VALID PRICES ========== //

    function test_whenThreePrices_whenStrictMode() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18;
        prices[2] = 3 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, _encodeStrictModeParams(true));
        assertEq(price, 2e18, "should return median in strict mode with three prices");
    }
}
