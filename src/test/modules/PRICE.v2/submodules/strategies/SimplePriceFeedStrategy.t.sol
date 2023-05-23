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

    function encodeDeviationParams(uint256 deviationBps)
        internal
        pure
        returns (bytes memory params)
    {
        return abi.encode(deviationBps);
    }

    function expectRevert(bytes4 selector_) internal {
        bytes memory err = abi.encodeWithSelector(selector_);
        vm.expectRevert(err);
    }

    // =========  TESTS - FIRST PRICE ========= //

    function test_getFirstPrice_revertsOnArrayLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getFirstPrice(prices, "");
    }

    function test_getFirstPrice_revertsOnPriceZero() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 0;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceZero.selector);

        strategy.getFirstPrice(prices, "");
    }

    function test_getFirstPrice_success() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1e18;

        uint256 price = strategy.getFirstPrice(prices, "");

        assertEq(price, 1e18);
    }

    // =========  TESTS - AVERAGE ========= //

    function test_getAveragePrice_revertsOnArrayLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getAveragePrice(prices, "");
    }

    function test_getAveragePrice_revertsOnPriceZeroFuzz(uint8 priceZeroIndex_) public {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 2, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else {
                prices[i] = 1e18;
            }
        }

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceZero.selector);

        strategy.getAveragePrice(prices, "");
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

        assertEq(price, 15 * 10**17);
    }

    function test_getAveragePrice_lengthOdd() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1e18;
        prices[1] = 2e18;
        prices[2] = 3e18;

        uint256 price = strategy.getAveragePrice(prices, "");

        assertEq(price, 2e18);
    }

    // =========  TESTS - MEDIAN ========= //

    function test_getMedianPrice_revertsOnPriceZeroFuzz(uint8 priceZeroIndex_) public {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 0, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else {
                prices[i] = 1e18;
            }
        }

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceZero.selector);

        strategy.getMedianPrice(prices, "");
    }

    function test_getMedianPrice_revertsOnLengthZero() public {
        uint256[] memory prices = new uint256[](0);

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

    function test_getMedianPrice_lengthOne() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");
        assertEq(price, 1 * 1e18);
    }

    function test_getMedianPrice_lengthTwo() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");
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

    function test_getMedianPrice_lengthEven() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 4 * 1e18;
        prices[1] = 2 * 1e18;
        prices[2] = 1 * 1e18;
        prices[3] = 3 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");
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

        strategy.getAverageIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
    }

    function test_getAverageIfDeviation_revertsOnPriceZeroFuzz(uint8 priceZeroIndex_) public {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 2, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else {
                prices[i] = 1e18;
            }
        }

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceZero.selector);

        strategy.getAverageIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
    }

    function test_getAverageIfDeviation_threeItems_deviationIndexOne() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getAverageIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
        assertEq(price, (1 * 1e18 + 1.2 * 1e18 + 1.001 * 1e18) / 3);
    }

    function test_getAverageIfDeviation_threeItems_deviationIndexTwo() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.2 * 1e18; // > 1% deviation

        uint256 price = strategy.getAverageIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
        assertEq(price, (1 * 1e18 + 1.001 * 1e18 + 1.2 * 1e18) / 3);
    }

    function test_getAverageIfDeviation_twoItems() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18; // > 1% deviation

        uint256 price = strategy.getAverageIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
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

        uint256 price = strategy.getAverageIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
        assertEq(price, 1 * 1e18);
    }

    // =========  TESTS - MEDIAN IF DEVIATION ========= //

    function test_getMedianIfDeviation_revertsOnLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getMedianIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
    }

    function test_getMedianIfDeviation_revertsOnPriceZeroFuzz(uint8 priceZeroIndex_) public {
        uint8 priceZeroIndex = uint8(bound(priceZeroIndex_, 2, 9));

        uint256[] memory prices = new uint256[](10);
        for (uint8 i = 0; i < 10; i++) {
            if (i == priceZeroIndex) {
                prices[i] = 0;
            } else {
                prices[i] = 1e18;
            }
        }

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceZero.selector);

        strategy.getMedianIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
    }

    function test_getMedianIfDeviation_fourItems() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;
        prices[3] = 0.99 * 1e18;

        uint256 price = strategy.getMedianIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
        assertEq(price, (1 * 1e18 + 1.001 * 1e18) / 2); // Average of the middle two
    }

    function test_getMedianIfDeviation_threeItems_deviationIndexOne() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getMedianIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianIfDeviation_threeItems_deviationIndexTwo() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.2 * 1e18; // > 1% deviation

        uint256 price = strategy.getMedianIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianIfDeviation_twoItems() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18; // > 1% deviation

        uint256 price = strategy.getMedianIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
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

        uint256 price = strategy.getMedianIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
        assertEq(price, 1 * 1e18);
    }

    function test_getMedianIfDeviation_revertsOnLengthOne() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1 * 1e18;

        expectRevert(SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector);

        strategy.getMedianIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
    }
}
