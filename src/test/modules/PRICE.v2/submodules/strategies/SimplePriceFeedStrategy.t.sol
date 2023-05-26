// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";

import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";

contract SimplePriceFeedStrategyTest is Test {
    using ModuleTestFixtureGenerator for SimplePriceFeedStrategy;

    MockPrice internal mockPrice;

    SimplePriceFeedStrategy internal strategy;

    uint8 internal PRICE_DECIMALS = 18;

    function setUp() public {
        Kernel kernel = new Kernel();
        mockPrice = new MockPrice(kernel, uint8(18), uint32(8 hours));
        mockPrice.setTimestamp(uint48(block.timestamp));
        mockPrice.setPriceDecimals(PRICE_DECIMALS);

        strategy = new SimplePriceFeedStrategy(mockPrice);
    }

    // =========  HELPER METHODS ========= //

    function encodeDeviationParams(
        uint256 deviationBps
    ) internal pure returns (bytes memory params) {
        return abi.encode(deviationBps);
    }

    function expectRevert(bytes4 selector_) internal {
        bytes memory err = abi.encodeWithSelector(selector_);
        vm.expectRevert(err);
    }

    // =========  TESTS - FIRST PRICE ========= //

    function test_getFirstNonZeroPrice_revertsOnArrayLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getFirstNonZeroPrice(prices, "");
    }

    function test_getFirstNonZeroPrice_revertsOnPriceZero() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 0;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getFirstNonZeroPrice(prices, "");
    }

    function test_getFirstNonZeroPrice_success() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1e18;

        uint256 price = strategy.getFirstNonZeroPrice(prices, "");

        assertEq(price, 1e18);
    }

    // =========  TESTS - AVERAGE ========= //

    function test_getAveragePrice_revertsOnArrayLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getAveragePrice(prices, "");
    }

    function test_getAveragePrice_revertsOnArrayPriceZero() public {
        uint256[] memory prices = new uint256[](2);

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getAveragePrice(prices, "");
    }

    function test_getAveragePrice_priceZeroFuzz(uint8 priceZeroIndex_) public {
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

    function test_getAveragePrice_lengthOne() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1e18;

        uint256 price = strategy.getAveragePrice(prices, "");

        assertEq(price, 1e18);
    }

    function test_getAveragePrice_lengthEven() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1e18;
        prices[1] = 2e18;

        uint256 price = strategy.getAveragePrice(prices, "");

        assertEq(price, 15 * 10 ** 17);
    }

    function test_getAveragePrice_lengthOdd() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 2e18;
        prices[2] = 3e18;

        uint256 price = strategy.getAveragePrice(prices, "");

        assertEq(price, 2e18);
    }

    function test_getAveragePrice_lengthOdd_priceZero() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1e18;
        prices[1] = 2e18;
        prices[2] = 0;
        prices[3] = 3e18;

        uint256 price = strategy.getAveragePrice(prices, "");

        // Ignores the zero price
        assertEq(price, 2e18);
    }

    // =========  TESTS - MEDIAN ========= //

    function test_getMedianPrice_priceZeroFuzz(uint8 priceZeroIndex_) public {
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

    function test_getMedianPrice_revertsOnArrayLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getMedianPrice(prices, "");
    }

    function test_getMedianPrice_revertsOnArrayEmpty() public {
        uint256[] memory prices = new uint256[](3);

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getMedianPrice(prices, "");
    }

    function test_getMedianPrice_unsorted() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 3 * 1e18;
        prices[1] = 1 * 1e18;
        prices[2] = 1.2 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");
        assertEq(price, 1.2 * 1e18);
    }

    function test_getMedianPrice_unsorted_priceZero() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 3 * 1e18;
        prices[1] = 1 * 1e18;
        prices[2] = 0;
        prices[3] = 1.2 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price
        assertEq(price, 1.2 * 1e18);
    }

    function test_getMedianPrice_lengthOne() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");
        assertEq(price, 1 * 1e18);
    }

    function test_getMedianPrice_lengthOne_priceZero() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 0;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price
        assertEq(price, 1 * 1e18);
    }

    function test_getMedianPrice_lengthTwo() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");
        assertEq(price, (1 * 1e18 + 2 * 1e18) / 2);
    }

    function test_getMedianPrice_lengthTwo_priceZero() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18;
        prices[2] = 0;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price
        assertEq(price, (1 * 1e18 + 2 * 1e18) / 2);
    }

    function test_getMedianPrice_lengthOdd() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18;
        prices[2] = 3 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");
        assertEq(price, 1.2 * 1e18);
    }

    function test_getMedianPrice_lengthOdd_priceZero() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18;
        prices[2] = 0;
        prices[3] = 3 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price
        assertEq(price, 1.2 * 1e18);
    }

    function test_getMedianPrice_lengthEven() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 4 * 1e18;
        prices[1] = 2 * 1e18;
        prices[2] = 1 * 1e18;
        prices[3] = 3 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");
        assertEq(price, (2 * 1e18 + 3 * 1e18) / 2);
    }

    function test_getMedianPrice_lengthEven_priceZero() public {
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

    // =========  TESTS - AVERAGE IF DEVIATION ========= //

    function test_getAverageIfDeviation_revertsOnLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getAverageIfDeviation(prices, encodeDeviationParams(100));
    }

    function test_getAverageIfDeviation_revertsOnLengthOne() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1 * 1e18;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getAverageIfDeviation(prices, encodeDeviationParams(100));
    }

    function test_getAverageIfDeviation_revertsOnLengthOne_priceZero() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0;
        prices[1] = 1 * 1e18;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getAverageIfDeviation(prices, encodeDeviationParams(100));
    }

    function test_getAverageIfDeviation_priceZeroFuzz(uint8 priceZeroIndex_) public {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 2, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else {
                prices[i] = 1e18;
            }
        }

        uint256 averagePrice = strategy.getAverageIfDeviation(prices, encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(averagePrice, 1e18);
    }

    function test_getAverageIfDeviation_threeItems_deviationIndexOne() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getAverageIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.2 * 1e18 + 1.001 * 1e18) / 3);
    }

    function test_getAverageIfDeviation_threeItems_priceZero() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;
        prices[3] = 1.001 * 1e18;

        uint256 price = strategy.getAverageIfDeviation(prices, encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(price, (1 * 1e18 + 1.2 * 1e18 + 1.001 * 1e18) / 3);
    }

    function test_getAverageIfDeviation_threeItems_deviationIndexTwo() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.2 * 1e18; // > 1% deviation

        uint256 price = strategy.getAverageIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.001 * 1e18 + 1.2 * 1e18) / 3);
    }

    function test_getAverageIfDeviation_twoItems() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18; // > 1% deviation

        uint256 price = strategy.getAverageIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 2 * 1e18) / 2);
    }

    function test_getAverageIfDeviation_revertsOnMissingParams() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_ParamsRequired.selector);

        strategy.getAverageIfDeviation(prices, "");
    }

    function test_getAverageIfDeviation_revertsOnMissingParamsDeviationBpsZero() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_ParamsRequired.selector);

        strategy.getAverageIfDeviation(prices, encodeDeviationParams(0));
    }

    function test_getAverageIfDeviation_withoutDeviation() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18; // < 1% deviation

        uint256 price = strategy.getAverageIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1 * 1e18);
    }

    // =========  TESTS - MEDIAN IF DEVIATION ========= //

    function test_getMedianIfDeviation_revertsOnArrayLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));
    }

    function test_getMedianIfDeviation_revertsOnArrayEmpty() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0;
        prices[1] = 0;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));
    }

    function test_getMedianIfDeviation_priceZeroFuzz(uint8 priceZeroIndex_) public {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 2, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else {
                prices[i] = 1e18;
            }
        }

        uint256 medianPrice = strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(medianPrice, 1e18);
    }

    function test_getMedianIfDeviation_fourItems() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;
        prices[3] = 0.99 * 1e18;

        uint256 price = strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.001 * 1e18) / 2); // Average of the middle two
    }

    function test_getMedianIfDeviation_fourItems_priceZero() public {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;
        prices[3] = 1.001 * 1e18;
        prices[4] = 0.99 * 1e18;

        uint256 price = strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(price, (1 * 1e18 + 1.001 * 1e18) / 2); // Average of the middle two
    }

    function test_getMedianIfDeviation_threeItems_deviationIndexOne() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianIfDeviation_threeItems_deviationIndexOne_priceZero() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;
        prices[3] = 1.001 * 1e18;

        uint256 price = strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianIfDeviation_threeItems_deviationIndexTwo() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.2 * 1e18; // > 1% deviation

        uint256 price = strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianIfDeviation_twoItems() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18; // > 1% deviation

        uint256 price = strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 2 * 1e18) / 2); // Average of the middle two
    }

    function test_getMedianIfDeviation_revertsOnMissingParams() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_ParamsRequired.selector);

        strategy.getMedianIfDeviation(prices, "");
    }

    function test_getMedianIfDeviation_revertsOnMissingParamsDeviationBpsZero() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_ParamsRequired.selector);

        strategy.getMedianIfDeviation(prices, encodeDeviationParams(0));
    }

    function test_getMedianIfDeviation_withoutDeviation() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18; // < 1% deviation

        uint256 price = strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1 * 1e18);
    }

    function test_getMedianIfDeviation_revertsOnLengthOne() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1 * 1e18;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));
    }

    function test_getMedianIfDeviation_revertsOnLengthOne_priceZero() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0;
        prices[1] = 1 * 1e18;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getMedianIfDeviation(prices, encodeDeviationParams(100));
    }

    // =========  TESTS - GET PRICE WITH FALLBACK ========= //

    function testFuzz_getPriceWithFallback_revertsOnLengthNotTwo(uint8 len) public {
        vm.assume(len <= 10 && len != 2);
        uint256[] memory prices = new uint256[](len);
        for (uint8 i; i < len; i++) {
            prices[i] = 1e18;
        }

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getPriceWithFallback(prices, encodeDeviationParams(100));
    }

    function test_getPriceWithFallback_validFirstPrice() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 11e18;
        prices[1] = 10e18;

        uint256 price = strategy.getPriceWithFallback(prices, encodeDeviationParams(100));
        assertEq(price, 11e18);
    }

    function test_getPriceWithFallback_invalidFirstPrice() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0;
        prices[1] = 10e18;

        uint256 price = strategy.getPriceWithFallback(prices, encodeDeviationParams(100));
        assertEq(price, 10e18);
    }

    function test_getPriceWithFallback_invalidSecondPrice() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 11e18;
        prices[1] = 0;

        uint256 price = strategy.getPriceWithFallback(prices, encodeDeviationParams(100));
        assertEq(price, 11e18);
    }

    function test_getPriceWithFallback_bothPricesInvalid() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0;
        prices[1] = 0;

        uint256 price = strategy.getPriceWithFallback(prices, encodeDeviationParams(100));
        assertEq(price, 0);
    }

    function testFuzz_getPriceWithFallback(uint256 firstPrice_, uint256 secondPrice_) public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = firstPrice_;
        prices[1] = secondPrice_;

        uint256 price = strategy.getPriceWithFallback(prices, encodeDeviationParams(100));
        if (firstPrice_ == 0) {
            assertEq(price, secondPrice_);
        } else {
            assertEq(price, firstPrice_);
        }
    }
}
