// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";
import {MockPrice} from "test/mocks/MockPrice.v2.sol";

import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";
import {FullMath} from "libraries/FullMath.sol";
import {Math} from "src/libraries/Balancer/math/Math.sol";
import {QuickSort} from "libraries/QuickSort.sol";

contract SimplePriceFeedStrategyTest is Test {
    using ModuleTestFixtureGenerator for SimplePriceFeedStrategy;
    using Math for uint256;
    using FullMath for uint256;
    using QuickSort for uint256[];

    MockPrice internal mockPrice;

    SimplePriceFeedStrategy internal strategy;

    uint8 internal constant PRICE_DECIMALS = 18;

    uint256 internal constant DEVIATION_MIN = 0;
    uint256 internal constant DEVIATION_MAX = 10_000;

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

    function expectRevertParams(bytes memory params_) internal {
        bytes memory err = abi.encodeWithSelector(
            SimplePriceFeedStrategy.SimpleStrategy_ParamsInvalid.selector,
            params_
        );
        vm.expectRevert(err);
    }

    function expectRevertPriceCount(uint256 pricesLen_, uint256 minPricesLen_) internal {
        bytes memory err = abi.encodeWithSelector(
            SimplePriceFeedStrategy.SimpleStrategy_PriceCountInvalid.selector,
            pricesLen_,
            minPricesLen_
        );
        vm.expectRevert(err);
    }

    /// @notice                 Indicates whether the supplied values are deviating
    /// @param deviationBps_    The deviation in basis points, where 0 = 0% and 10_000 = 100%
    function _isDeviating(
        uint256 valueOne_,
        uint256 referenceValue_,
        uint256 deviationBps_
    ) internal pure returns (bool) {
        uint256 largerValue = valueOne_.max(referenceValue_);
        uint256 smallerValue = valueOne_.min(referenceValue_);

        // 10_000 = 100%
        uint256 deviationBase = 10_000;

        return (largerValue - smallerValue).mulDiv(deviationBase, referenceValue_) > deviationBps_;
    }

    // =========  TESTS - FIRST PRICE ========= //

    function test_getFirstNonZeroPrice_revertsOnArrayLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        expectRevertPriceCount(0, 1);

        strategy.getFirstNonZeroPrice(prices, "");
    }

    function test_getFirstNonZeroPrice_pricesInvalid(uint8 len_) public {
        uint8 len = uint8(bound(len_, 1, 10));

        uint256[] memory prices = new uint256[](len);
        for (uint8 i; i < len; i++) {
            prices[i] = 0;
        }

        uint256 returnedPrice = strategy.getFirstNonZeroPrice(prices, "");
        assertEq(returnedPrice, 0);
    }

    function test_getFirstNonZeroPrice_success() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1e18;

        uint256 price = strategy.getFirstNonZeroPrice(prices, "");

        assertEq(price, 1e18);
    }

    function testFuzz_getFirstNonZeroPrice_arrayLengthGreaterThanTwo(uint8 len) public {
        vm.assume(len > 2 && len <= 10);
        uint256[] memory prices = new uint256[](len);
        for (uint8 i; i < len; i++) {
            prices[i] = 1e18;
        }

        uint256 price = strategy.getFirstNonZeroPrice(prices, "");

        assertEq(price, 1e18);
    }

    function test_getFirstNonZeroPrice_validFirstPrice() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 11e18;
        prices[1] = 10e18;

        uint256 price = strategy.getFirstNonZeroPrice(prices, encodeDeviationParams(100));
        assertEq(price, 11e18);
    }

    function test_getFirstNonZeroPrice_invalidFirstPrice() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0;
        prices[1] = 10e18;

        uint256 price = strategy.getFirstNonZeroPrice(prices, encodeDeviationParams(100));
        assertEq(price, 10e18);
    }

    function test_getFirstNonZeroPrice_invalidSecondPrice() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 11e18;
        prices[1] = 0;

        uint256 price = strategy.getFirstNonZeroPrice(prices, encodeDeviationParams(100));
        assertEq(price, 11e18);
    }

    function testFuzz_getFirstNonZeroPrice(uint256 firstPrice_, uint256 secondPrice_) public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = firstPrice_;
        prices[1] = secondPrice_;

        uint256 price = strategy.getFirstNonZeroPrice(prices, encodeDeviationParams(100));
        if (firstPrice_ == 0) {
            assertEq(price, secondPrice_);
        } else {
            assertEq(price, firstPrice_);
        }
    }

    // =========  TESTS - AVERAGE ========= //

    function test_getAveragePrice_revertsOnArrayLengthInvalid(uint8 len_) public {
        uint8 len = uint8(bound(len_, 0, 1));
        uint256[] memory prices = new uint256[](len);

        expectRevertPriceCount(len, 2);

        strategy.getAveragePrice(prices, "");
    }

    function test_getAveragePrice_empty_fuzz(uint8 len_) public {
        uint8 len = uint8(bound(len_, 2, 10));
        uint256[] memory prices = new uint256[](len);

        uint256 returnedPrice = strategy.getAveragePrice(prices, "");
        assertEq(returnedPrice, 0);
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

    function test_getAveragePrice_lengthEven_priceZero() public {
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

    function test_getMedianPrice_priceZero_indexFuzz(uint8 priceZeroIndex_) public {
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

        expectRevertPriceCount(len, 3);
        strategy.getMedianPrice(prices, "");
    }

    function test_getMedianPrice_empty_fuzz(uint8 len_) public {
        uint8 len = uint8(bound(len_, 3, 10));
        uint256[] memory prices = new uint256[](len);

        uint256 returnedPrice = strategy.getMedianPrice(prices, "");
        assertEq(returnedPrice, 0);
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

    function test_getMedianPrice_arrayLengthValid_priceDoubleZero() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 0;
        prices[2] = 0;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price
        assertEq(price, 1e18);
    }

    function test_getMedianPrice_arrayLengthValid_priceSingleZero() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18;
        prices[2] = 0;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price and returns the first non-zero price
        assertEq(price, 1e18);
    }

    function test_getMedianPrice_arrayLengthValid_priceSingleZero_indexZero() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1 * 1e18;
        prices[2] = 2 * 1e18;

        uint256 price = strategy.getMedianPrice(prices, "");

        // Ignores the zero price and returns the first non-zero price
        assertEq(price, 1e18);
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

    function test_getAveragePriceIfDeviation_revertsOnArrayLengthZero() public {
        uint256[] memory prices = new uint256[](0);

        expectRevertPriceCount(0, 2);

        strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));
    }

    function test_getAveragePriceIfDeviation_revertsOnArrayLengthOne() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1 * 1e18;

        expectRevertPriceCount(1, 2);

        strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));
    }

    function test_getAveragePriceIfDeviation_empty_fuzz(uint8 len_) public {
        uint8 len = uint8(bound(len_, 2, 10));

        uint256[] memory prices = new uint256[](len);

        uint256 returnedPrice = strategy.getAveragePriceIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
        assertEq(returnedPrice, 0);
    }

    function test_getAveragePriceIfDeviation_arrayLengthTwo_singlePriceZero() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0;
        prices[1] = 1 * 1e18;

        uint256 returnedPrice = strategy.getAveragePriceIfDeviation(
            prices,
            encodeDeviationParams(100)
        );

        // Ignores the zero price
        assertEq(returnedPrice, 1e18);
    }

    function test_getAveragePriceIfDeviation_priceZeroFuzz(uint8 priceZeroIndex_) public {
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
            encodeDeviationParams(100)
        );

        // Ignores the zero price
        assertEq(averagePrice, 1e18);
    }

    function test_getAveragePriceIfDeviation_threeItems_fuzz(
        uint256 priceOne_,
        uint256 priceTwo_,
        uint256 priceThree_
    ) public {
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
            encodeDeviationParams(deviationBps)
        );
        assertEq(price, expectedPrice);
    }

    function test_getAveragePriceIfDeviation_threeItems_deviationIndexOne() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.2 * 1e18 + 1.001 * 1e18) / 3);
    }

    function test_getAveragePriceIfDeviation_threeItems_priceZero() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;
        prices[3] = 1.001 * 1e18;

        uint256 price = strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(price, (1 * 1e18 + 1.2 * 1e18 + 1.001 * 1e18) / 3);
    }

    function test_getAveragePriceIfDeviation_threeItems_deviationIndexTwo() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.2 * 1e18; // > 1% deviation

        uint256 price = strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.001 * 1e18 + 1.2 * 1e18) / 3);
    }

    function test_getAveragePriceIfDeviation_twoItems() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 2 * 1e18; // > 1% deviation

        uint256 price = strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 2 * 1e18) / 2);
    }

    function test_getAveragePriceIfDeviation_revertsOnMissingParams() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;

        expectRevertParams("");

        strategy.getAveragePriceIfDeviation(prices, "");
    }

    function test_getAveragePriceIfDeviation_paramsDeviationBps_fuzz(uint256 deviationBps_) public {
        uint256 deviationBps = bound(deviationBps_, DEVIATION_MIN, DEVIATION_MAX * 2);

        bool isDeviationInvalid = deviationBps <= DEVIATION_MIN || deviationBps >= DEVIATION_MAX;

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.002 * 1e18;

        if (isDeviationInvalid) expectRevertParams(encodeDeviationParams(deviationBps));

        strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(deviationBps));
    }

    function test_getAveragePriceIfDeviation_revertsOnMissingParamsDeviationBpsEmpty() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;

        expectRevertParams(abi.encode(""));

        strategy.getAveragePriceIfDeviation(prices, abi.encode(""));
    }

    function test_getAveragePriceIfDeviation_withoutDeviation() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18; // < 1% deviation

        uint256 price = strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1 * 1e18);
    }

    // =========  TESTS - MEDIAN IF DEVIATION ========= //

    function test_getMedianPriceIfDeviation_revertsOnArrayLengthInvalid(uint8 len_) public {
        uint8 len = uint8(bound(len_, 0, 2));
        uint256[] memory prices = new uint256[](len);

        expectRevertPriceCount(len, 3);

        strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
    }

    function test_getMedianPriceIfDeviation_priceZero_indexFuzz(uint8 priceZeroIndex_) public {
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
            encodeDeviationParams(100)
        );

        // Ignores the zero price
        assertEq(medianPrice, 1e18);
    }

    function test_getMedianPriceIfDeviation_empty_fuzz(uint8 len_) public {
        uint8 len = uint8(bound(len_, 3, 10));
        uint256[] memory prices = new uint256[](len);

        uint256 medianPrice = strategy.getMedianPriceIfDeviation(
            prices,
            encodeDeviationParams(100)
        );

        // Handles the zero price
        assertEq(medianPrice, 0);
    }

    function test_getMedianPriceIfDeviation_fourItems() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;
        prices[3] = 0.99 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.001 * 1e18) / 2); // Average of the middle two
    }

    function test_getMedianPriceIfDeviation_fiveItems_priceZero() public {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;
        prices[3] = 1.001 * 1e18;
        prices[4] = 0.99 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(price, (1 * 1e18 + 1.001 * 1e18) / 2); // Average of the middle two
    }

    function test_getMedianPriceIfDeviation_threeItems_fuzz(
        uint256 priceOne_,
        uint256 priceTwo_,
        uint256 priceThree_
    ) public {
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
            encodeDeviationParams(deviationBps)
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

    function test_getMedianPriceIfDeviation_threeItems_deviationIndexOne() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianPriceIfDeviation_threeItems_priceZero() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 0;
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1e18); // < 3 non-zero items, returns first non-zero item
    }

    function test_getMedianPriceIfDeviation_threeItems_priceZero_indexZero() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1 * 1e18;
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1e18); // < 3 non-zero items, returns first non-zero item
    }

    function test_getMedianPriceIfDeviation_fourItems_deviationIndexOne_priceZero() public {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;
        prices[3] = 1.001 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianPriceIfDeviation_threeItems_deviationIndexTwo() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.2 * 1e18; // > 1% deviation

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianPriceIfDeviation_revertsOnMissingParams() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.002 * 1e18;

        expectRevertParams("");

        strategy.getMedianPriceIfDeviation(prices, "");
    }

    function test_getMedianPriceIfDeviation_revertsOnMissingParamsDeviationBpsEmpty() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.002 * 1e18;

        expectRevertParams(abi.encode(""));

        strategy.getMedianPriceIfDeviation(prices, abi.encode(""));
    }

    function test_getMedianPriceIfDeviation_paramsDeviationBps_fuzz(uint256 deviationBps_) public {
        uint256 deviationBps = bound(deviationBps_, DEVIATION_MIN, DEVIATION_MAX * 2);

        bool isDeviationInvalid = deviationBps <= DEVIATION_MIN || deviationBps >= DEVIATION_MAX;

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.002 * 1e18;

        if (isDeviationInvalid) expectRevertParams(encodeDeviationParams(deviationBps));

        strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(deviationBps));
    }

    function test_getMedianPriceIfDeviation_withoutDeviation() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18; // < 1% deviation
        prices[2] = 1.002 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        // No deviation, so returns the first price
        assertEq(price, 1 * 1e18);
    }
}
