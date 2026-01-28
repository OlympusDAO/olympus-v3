// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

/// @title Tests for getAveragePrice function
/// @notice Tests the average price aggregation strategy
contract SimplePriceFeedStrategyGetAveragePriceTest is SimplePriceFeedStrategyBase {
    // =========  TESTS ========= //

    // ========== CONFIGURATION ERRORS ========== //
    // when input array length is less than 2
    //   [X] it reverts
    // when params are empty
    //   [X] it reverts
    // when params length is not 32 bytes
    //   [X] it reverts

    function test_whenInvalidArrayLength_reverts(uint8 len_) public {
        uint8 len = uint8(bound(len_, 0, 1));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(len, 2);
        strategy.getAveragePrice(prices, _encodeStrictModeParams(false));
    }

    function test_whenEmptyParams_reverts() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 2e18;

        _expectRevertParams("");
        strategy.getAveragePrice(prices, "");
    }

    function test_whenInvalidParamsLength_reverts() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 2e18;

        bytes memory invalidParams = abi.encode(uint256(123), uint256(456)); // 64 bytes

        _expectRevertParams(invalidParams);
        strategy.getAveragePrice(prices, invalidParams);
    }

    // ========== ALL PRICES ZERO ========== //
    // when all prices are zero
    //   [X] it reverts

    function test_whenAllPricesZero_reverts(uint8 len_) public {
        uint8 len = uint8(bound(len_, 2, 10));
        uint256[] memory prices = new uint256[](len);

        _expectRevertPriceCount(0, 2);
        strategy.getAveragePrice(prices, _encodeStrictModeParams(false));
    }

    // ========== ONE NON-ZERO PRICE ========== //
    // when one non-zero price
    //   when strict mode is enabled
    //     [X] it reverts
    //   when strict mode is disabled
    //     [X] it returns that price

    function test_whenOneNonZeroPrice_whenStrictMode_reverts(uint8 arrayLen_) public {
        uint8 arrayLen = uint8(bound(arrayLen_, 2, 10));
        uint256[] memory prices = new uint256[](arrayLen);
        prices[arrayLen - 1] = 1e18;

        _expectRevertPriceCount(1, 2);
        strategy.getAveragePrice(prices, _encodeStrictModeParams(true));
    }

    function test_whenOneNonZeroPrice(uint8 arrayLen_) public view {
        uint8 arrayLen = uint8(bound(arrayLen_, 2, 10));
        uint256[] memory prices = new uint256[](arrayLen);
        prices[arrayLen - 1] = 1.5e18;

        uint256 price = strategy.getAveragePrice(prices, _encodeStrictModeParams(false));
        assertEq(price, 1.5e18, "should return the single non-zero price");
    }

    // ========== TWO NON-ZERO PRICES ========== //
    // when two non-zero prices
    //   [X] it returns the average

    function test_whenTwoPrices(uint8 strictMode_) public view {
        bool strictMode = strictMode_ % 2 == 0;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 2e18;

        uint256 price = strategy.getAveragePrice(prices, _encodeStrictModeParams(strictMode));
        // (1e18 + 2e18) / 2 = 1.5e18
        assertEq(price, 1.5e18, "should return average of two prices");
    }

    // ========== THREE+ NON-ZERO PRICES ========== //
    // when three non-zero prices
    //   [X] it returns the average
    // when four prices with one zero
    //   [X] it ignores zero and returns average

    function test_whenThreePrices(uint8 strictMode_) public view {
        bool strictMode = strictMode_ % 2 == 0;
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 2e18;
        prices[2] = 3e18;

        uint256 price = strategy.getAveragePrice(prices, _encodeStrictModeParams(strictMode));
        // (1e18 + 2e18 + 3e18) / 3 = 2e18
        assertEq(price, 2e18, "should return average of three prices");
    }

    function test_whenFourPrices_oneZero() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1e18;
        prices[1] = 2e18;
        prices[2] = 0;
        prices[3] = 3e18;

        uint256 price = strategy.getAveragePrice(prices, _encodeStrictModeParams(false));
        // (1e18 + 2e18 + 3e18) / 3 = 2e18
        assertEq(price, 2e18, "should ignore zero and return average of non-zero prices");
    }

    function test_whenOnePriceZero_outOfTen(uint8 priceZeroIndex_) public view {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 0, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            prices[i] = i == priceZeroIndex ? 0 : 1e18;
        }

        uint256 averagePrice = strategy.getAveragePrice(prices, _encodeStrictModeParams(false));
        assertEq(averagePrice, 1e18, "should ignore zero price and return average");
    }
}
