// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

// Mocks
import {MockPrice} from "test/mocks/MockPrice.v2.sol";

// Libraries
import {FullMath} from "libraries/FullMath.sol";
import {Math} from "src/libraries/Balancer/math/Math.sol";
import {QuickSort} from "libraries/QuickSort.sol";

// Bophades
import {Kernel} from "src/Kernel.sol";
import {SimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/SimplePriceFeedStrategy.sol";
import {ISimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";

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

    function encodeDeviationParams(
        uint16 deviationBps,
        bool revertOnInsufficientCount
    ) internal pure returns (bytes memory params) {
        ISimplePriceFeedStrategy.DeviationParams memory p = ISimplePriceFeedStrategy
            .DeviationParams({
                deviationBps: deviationBps,
                revertOnInsufficientCount: revertOnInsufficientCount
            });
        return abi.encode(p);
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

    function testFuzz_getFirstNonZeroPrice_arrayLengthGreaterThanTwo(uint8 len) public view {
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

        uint256 price = strategy.getFirstNonZeroPrice(prices, encodeDeviationParams(100));
        assertEq(price, 11e18);
    }

    function test_getFirstNonZeroPrice_invalidFirstPrice() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0;
        prices[1] = 10e18;

        uint256 price = strategy.getFirstNonZeroPrice(prices, encodeDeviationParams(100));
        assertEq(price, 10e18);
    }

    function test_getFirstNonZeroPrice_invalidSecondPrice() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 11e18;
        prices[1] = 0;

        uint256 price = strategy.getFirstNonZeroPrice(prices, encodeDeviationParams(100));
        assertEq(price, 11e18);
    }

    function testFuzz_getFirstNonZeroPrice(uint256 firstPrice_, uint256 secondPrice_) public view {
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

    // =========  TESTS - MEDIAN ========= //

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

        expectRevertPriceCount(len, 3);
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

    function test_getAveragePriceIfDeviation_empty_fuzz(uint8 len_) public view {
        uint8 len = uint8(bound(len_, 2, 10));

        uint256[] memory prices = new uint256[](len);

        uint256 returnedPrice = strategy.getAveragePriceIfDeviation(
            prices,
            encodeDeviationParams(100)
        );
        assertEq(returnedPrice, 0);
    }

    function test_getAveragePriceIfDeviation_arrayLengthTwo_singlePriceZero() public view {
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
            encodeDeviationParams(100)
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
            encodeDeviationParams(deviationBps)
        );
        assertEq(price, expectedPrice);
    }

    function test_getAveragePriceIfDeviation_threeItems_deviationIndexOne() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.2 * 1e18 + 1.001 * 1e18) / 3);
    }

    function test_getAveragePriceIfDeviation_threeItems_priceZeroTwice() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;

        uint256 price = strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));

        // Returns first non-zero price
        assertEq(price, 1.2 * 1e18);
    }

    function test_getAveragePriceIfDeviation_threeItems_priceZero() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;

        uint256 price = strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));

        // Returns the average of the non-zero prices
        assertEq(price, (1 * 1e18 + 1.2 * 1e18) / 2);
    }

    function test_getAveragePriceIfDeviation_fourItems_priceZero() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;
        prices[3] = 1.001 * 1e18;

        uint256 price = strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(price, (1 * 1e18 + 1.2 * 1e18 + 1.001 * 1e18) / 3);
    }

    function test_getAveragePriceIfDeviation_threeItems_deviationIndexTwo() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18;
        prices[2] = 1.2 * 1e18; // > 1% deviation

        uint256 price = strategy.getAveragePriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.001 * 1e18 + 1.2 * 1e18) / 3);
    }

    function test_getAveragePriceIfDeviation_twoItems() public view {
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

    function test_getAveragePriceIfDeviation_withoutDeviation() public view {
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
            encodeDeviationParams(100)
        );

        // Ignores the zero price
        assertEq(medianPrice, 1e18);
    }

    function test_getMedianPriceIfDeviation_empty_fuzz(uint8 len_) public view {
        uint8 len = uint8(bound(len_, 3, 10));
        uint256[] memory prices = new uint256[](len);

        uint256 medianPrice = strategy.getMedianPriceIfDeviation(
            prices,
            encodeDeviationParams(100)
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

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.001 * 1e18) / 2); // Average of the middle two
    }

    function test_getMedianPriceIfDeviation_fiveItems_priceZero() public view {
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

    function test_getMedianPriceIfDeviation_threeItems_deviationIndexOne() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianPriceIfDeviation_threeItems_priceZero_deviation() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 0;
        prices[2] = 1.2 * 1e18; // > 1% deviation

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, (1 * 1e18 + 1.2 * 1e18) / 2); // < 3 non-zero items and deviating, returns average
    }

    function test_getMedianPriceIfDeviation_threeItems_priceZero() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 0;
        prices[2] = 1.001 * 1e18; // < 1% deviation

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1e18); // < 3 non-zero items, returns first non-zero price
    }

    function test_getMedianPriceIfDeviation_threeItems_priceZero_indexZero() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 1 * 1e18;
        prices[2] = 1.001 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        assertEq(price, 1e18); // < 3 non-zero items, returns first non-zero price
    }

    function test_getMedianPriceIfDeviation_fourItems_deviationIndexOne_priceZero() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 1 * 1e18;
        prices[1] = 1.2 * 1e18; // > 1% deviation
        prices[2] = 0;
        prices[3] = 1.001 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));

        // Ignores the zero price
        assertEq(price, 1.001 * 1e18);
    }

    function test_getMedianPriceIfDeviation_threeItems_deviationIndexTwo() public view {
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

    function test_getMedianPriceIfDeviation_withoutDeviation() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1 * 1e18;
        prices[1] = 1.001 * 1e18; // < 1% deviation
        prices[2] = 1.002 * 1e18;

        uint256 price = strategy.getMedianPriceIfDeviation(prices, encodeDeviationParams(100));
        // No deviation, so returns the first price
        assertEq(price, 1 * 1e18);
    }

    // =========  TESTS - AVERAGE PRICE EXCLUDING DEVIATIONS ========= //

    // ============================================================================
    // INPUT VALIDATION TESTS (Configuration Issues - always revert)
    // ============================================================================
    //
    // given input array has less than 3 elements
    //   [X] it reverts with PriceCountInvalid
    //

    function test_givenInputArrayLengthZero_getAveragePriceExcludingDeviations_reverts() public {
        uint256[] memory prices = new uint256[](0);
        bytes memory params = encodeDeviationParams(1000, false);

        expectRevertPriceCount(0, 3);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenInputArrayLengthOne_getAveragePriceExcludingDeviations_reverts() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1000e18;
        bytes memory params = encodeDeviationParams(1000, false);

        expectRevertPriceCount(1, 3);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenInputArrayLengthTwo_getAveragePriceExcludingDeviations_reverts() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        bytes memory params = encodeDeviationParams(1000, false);

        expectRevertPriceCount(2, 3);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenInputArrayLengthLessThanThree_fuzz_getAveragePriceExcludingDeviations_reverts(
        uint8 length,
        uint256 price1,
        uint256 price2
    ) public {
        vm.assume(length < 3);
        uint256[] memory prices = new uint256[](length);
        if (length > 0) prices[0] = price1;
        if (length > 1) prices[1] = price2;
        bytes memory params = encodeDeviationParams(1000, false);

        expectRevertPriceCount(length, 3);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    // ============================================================================
    // PARAMS VALIDATION TESTS
    // ============================================================================
    //
    // given params length is not 64 bytes
    //   [X] it reverts with ParamsInvalid
    //
    // given deviationBps is 0 or >= 10000
    //   [X] it reverts with ParamsInvalid
    //

    function test_givenParamsEmpty_getAveragePriceExcludingDeviations_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = "";

        expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenParamsLengthOne_getAveragePriceExcludingDeviations_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = hex"01";

        expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenParamsLengthThirtyTwo_getAveragePriceExcludingDeviations_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = hex"0000000000000000000000000000000000000000000000000000000000000001";

        expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenParamsLengthNinetySix_getAveragePriceExcludingDeviations_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        // 96 bytes = valid 64 bytes + 32 extra bytes
        bytes memory params = abi.encode(
            ISimplePriceFeedStrategy.DeviationParams({
                deviationBps: 1000,
                revertOnInsufficientCount: false
            })
        );
        bytes
            memory paramsExtra = hex"0000000000000000000000000000000000000000000000000000000000000001";
        bytes memory paramsExtended = bytes.concat(params, paramsExtra);

        expectRevertParams(paramsExtended);
        strategy.getAveragePriceExcludingDeviations(prices, paramsExtended);
    }

    function test_givenDeviationBpsZero_getAveragePriceExcludingDeviations_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = encodeDeviationParams(0, false);

        expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenDeviationBpsEqualsMax_getAveragePriceExcludingDeviations_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = encodeDeviationParams(10000, false);

        expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    // ============================================================================
    // ZERO PRICE HANDLING TESTS
    // ============================================================================
    //
    // given all prices are zero
    //   [X] it reverts with PriceCountInvalid
    //
    // given exactly 1 non-zero price (after zero filtering)
    //   given revertOnInsufficientCount is false
    //     [X] it returns the single non-zero price
    //   given revertOnInsufficientCount is true
    //     [X] it reverts with PriceCountInvalid
    //

    function test_givenAllPricesZero_getAveragePriceExcludingDeviations_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 0;
        prices[2] = 0;
        bytes memory params = encodeDeviationParams(1000, false);

        expectRevertPriceCount(0, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenThreePricesTwoZeros_givenFlagFalse_getAveragePriceExcludingDeviations()
        public
        view
    {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 0;
        prices[2] = 0;
        bytes memory params = encodeDeviationParams(1000, false);

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Expected: 1000e18 (only non-zero price)
        assertEq(result, 1000e18, "should return single non-zero price");
    }

    function test_givenThreePricesTwoZeros_givenFlagTrue_getAveragePriceExcludingDeviations_reverts()
        public
    {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 0;
        prices[2] = 0;
        bytes memory params = encodeDeviationParams(1000, true);

        expectRevertPriceCount(1, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    // ============================================================================
    // TWO-PRICE FALLBACK TESTS (Average as Benchmark)
    // ============================================================================
    //
    // given exactly 2 non-zero prices (after zero filtering)
    //   given neither price deviates from average
    //     [X] it returns the average of both prices
    //   given both prices deviate from average (tight threshold)
    //     [X] it reverts with PriceCountInvalid (no data)
    //   given neither price deviates (loose threshold)
    //     [X] it returns the average of both prices
    //

    function test_givenTwoNonZeroPrices_givenNoneDeviating_getAveragePriceExcludingDeviations()
        public
        view
    {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 0;
        bytes memory params = encodeDeviationParams(1000, false); // 10% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // average = (1000e18 + 1050e18) / 2 = 1025e18
        // Neither deviates from 1025e18 by more than 10%
        assertEq(result, 1025e18, "should return average of non-deviating prices");
    }

    function test_givenTwoNonZeroPrices_givenBothDeviating_getAveragePriceExcludingDeviations_reverts()
        public
    {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1500e18;
        prices[2] = 0;
        bytes memory params = encodeDeviationParams(500, false); // 5% deviation

        expectRevertPriceCount(0, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenTwoNonZeroPrices_givenOneDeviating_givenFlagFalse_getAveragePriceExcludingDeviations()
        public
        view
    {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1500e18; // ~40% deviation from average of 1250e18
        prices[2] = 0;
        bytes memory params = encodeDeviationParams(3000, false); // 30% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // average = (1000e18 + 1500e18) / 2 = 1250e18
        // 1000e18: |1000 - 1250| / 1250 = 20% < 30% -> Include
        // 1500e18: |1500 - 1250| / 1250 = 20% < 30% -> Include
        // Both included, return average
        assertEq(result, 1250e18, "should return average of both prices");
    }

    function test_givenTwoNonZeroPrices_wideDeviation_getAveragePriceExcludingDeviations_reverts()
        public
    {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1500e18; // 40% deviation from average of 1250e18
        prices[2] = 0;
        bytes memory params = encodeDeviationParams(1500, false); // 15% deviation

        // average = (1000e18 + 1500e18) / 2 = 1250e18
        // 1000e18: |1000 - 1250| / 1250 = 20% > 15% -> Exclude
        // 1500e18: |1500 - 1250| / 1250 = 20% > 15% -> Exclude
        // Both excluded -> revert (no data)
        expectRevertPriceCount(0, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenTwoNonZeroPrices_strictDeviation_getAveragePriceExcludingDeviations()
        public
        view
    {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1150e18;
        prices[2] = 0;
        bytes memory params = encodeDeviationParams(2000, false); // 20% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // average = (1000e18 + 1150e18) / 2 = 1075e18
        // 1000e18: |1000 - 1075| / 1075 = 6.98% < 20% -> Include
        // 1150e18: |1150 - 1075| / 1075 = 6.98% < 20% -> Include
        assertEq(result, 1075e18, "should return average of both prices");
    }

    // ============================================================================
    // BASIC FUNCTIONALITY TESTS (Median as Benchmark, 3+ prices)
    // ============================================================================
    //
    // given 3+ non-zero prices (median as benchmark)
    //   given no prices deviate from median
    //     [X] it returns the average of all prices
    //   given one price deviates from median
    //     [X] it returns the average of non-deviating prices
    //   given multiple prices deviate from median
    //     given 2+ prices remain after exclusion
    //       [X] it returns the average of remaining prices
    //
    // given even number of prices (4+)
    //   [X] it uses median of middle two values as benchmark
    //

    function test_givenThreePricesNoneDeviating_getAveragePriceExcludingDeviations() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = encodeDeviationParams(2000, false); // 20% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Sorted: [1000e18, 1050e18, 1200e18]
        // Median: 1050e18
        // Deviations from 1050e18:
        //   1000e18: |1000 - 1050| / 1050 = 4.76% < 20% -> Include
        //   1050e18: 0% -> Include
        //   1200e18: |1200 - 1050| / 1050 = 14.29% < 20% -> Include
        // Result: (1000e18 + 1050e18 + 1200e18) / 3
        uint256 sum = (1000e18 + 1050e18 + 1200e18);
        uint256 expected = FullMath.mulDiv(sum, 1, 3);
        assertEq(result, expected, "should return average of all non-deviating prices");
    }

    function test_givenThreePricesOneDeviating_getAveragePriceExcludingDeviations() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 5000e18; // Significant outlier
        bytes memory params = encodeDeviationParams(1000, false); // 10% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Sorted: [1000e18, 1050e18, 5000e18]
        // Median: 1050e18
        // Deviations from 1050e18:
        //   1000e18: |1000 - 1050| / 1050 = 4.76% < 10% -> Include
        //   1050e18: 0% -> Include
        //   5000e18: |5000 - 1050| / 1050 = 376% > 10% -> Exclude
        // Result: (1000e18 + 1050e18) / 2 = 1025e18
        assertEq(result, 1025e18, "should return average of non-deviating prices");
    }

    function test_givenFivePricesWithOutliers_getAveragePriceExcludingDeviations() public view {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        prices[3] = 950e18;
        prices[4] = 5000e18; // Outlier
        bytes memory params = encodeDeviationParams(1000, false); // 10% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Sorted: [950e18, 1000e18, 1050e18, 1200e18, 5000e18]
        // Median: 1050e18
        // Deviations from 1050e18:
        //   950e18: |950 - 1050| / 1050 = 9.52% < 10% -> Include
        //   1000e18: |1000 - 1050| / 1050 = 4.76% < 10% -> Include
        //   1050e18: 0% -> Include
        //   1200e18: |1200 - 1050| / 1050 = 14.29% > 10% -> Exclude
        //   5000e18: |5000 - 1050| / 1050 = 376% > 10% -> Exclude
        // Result: (950e18 + 1000e18 + 1050e18) / 3 = 1000e18
        assertEq(result, 1000e18, "should return average excluding outliers");
    }

    // ============================================================================
    // revertOnInsufficientCount FLAG TESTS
    // ============================================================================
    //
    // given 1 price remains after exclusion
    //   given revertOnInsufficientCount is false
    //     [X] it returns the remaining price
    //   given revertOnInsufficientCount is true
    //     [X] it reverts with PriceCountInvalid
    //
    // given 0 prices remain after exclusion (all deviate)
    //   [X] it reverts with PriceCountInvalid
    //

    function test_givenOneRemainsAfterExclusion_givenFlagFalse_getAveragePriceExcludingDeviations()
        public
        view
    {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 3000e18;
        bytes memory params = encodeDeviationParams(100, false); // 1% deviation - tight

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Sorted: [1000e18, 1050e18, 3000e18]
        // Median: 1050e18
        // Deviations from 1050e18:
        //   1000e18: 4.76% < 1% -> No, > 1% -> Exclude
        //   1050e18: 0% -> Include
        //   3000e18: 185% > 1% -> Exclude
        // Only median remains
        // With flag=false, return single remaining price
        assertEq(result, 1050e18, "should return single remaining price");
    }

    function test_givenOneRemainsAfterExclusion_givenFlagTrue_getAveragePriceExcludingDeviations_reverts()
        public
    {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 3000e18;
        bytes memory params = encodeDeviationParams(100, true); // 1% deviation, strict mode

        expectRevertPriceCount(1, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    // ============================================================================
    // EDGE CASE TESTS
    // ============================================================================

    // Note: The median price never deviates from itself (0% deviation), so it's
    // not possible for ALL prices to deviate when using median as benchmark.
    // This test verifies the strict mode behavior with tight deviation threshold.

    function test_givenTightDeviationOnlyMedianRemains_givenFlagTrue_getAveragePriceExcludingDeviations_reverts()
        public
    {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 3000e18;
        bytes memory params = encodeDeviationParams(100, true); // 1% deviation, strict mode

        // Sorted: [1000e18, 1050e18, 3000e18]
        // Median: 1050e18
        // Deviations from 1050e18:
        //   1000e18: 4.76% > 1% -> Exclude
        //   1050e18: 0% -> Include
        //   3000e18: 185% > 1% -> Exclude
        // Only median remains, flag=true -> revert
        expectRevertPriceCount(1, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenFourPricesEvenCount_getAveragePriceExcludingDeviations_usesMedian()
        public
        view
    {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 900e18;
        prices[1] = 1000e18;
        prices[2] = 1100e18;
        prices[3] = 5000e18;
        bytes memory params = encodeDeviationParams(1000, false); // 10% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Sorted: [900e18, 1000e18, 1100e18, 5000e18]
        // Median (even count): (1000e18 + 1100e18) / 2 = 1050e18
        // Deviations from 1050e18:
        //   900e18: |900 - 1050| / 1050 = 14.29% > 10% -> Exclude
        //   1000e18: |1000 - 1050| / 1050 = 4.76% < 10% -> Include
        //   1100e18: |1100 - 1050| / 1050 = 4.76% < 10% -> Include
        //   5000e18: |5000 - 1050| / 1050 = 376% > 10% -> Exclude
        // Result: (1000e18 + 1100e18) / 2 = 1050e18
        assertEq(result, 1050e18, "should use median as benchmark for even count");
    }

    // ============================================================================
    // FUZZ TESTS
    // ============================================================================
    //
    // fuzz tests
    //   [X] given random valid inputs (flag=false) - no revert
    //   [X] given random clustered inputs (flag=true) - no revert
    //
    // ============================================================================

    function testFuzz_givenThreePricesWithValidDeviation_getAveragePriceExcludingDeviations(
        uint64 price1,
        uint64 price2,
        uint64 price3,
        uint16 deviationBps
    ) public view {
        // Bound prices to reasonable range (1e9 to 1e19, scaled down)
        vm.assume(price1 >= 1e9 && price1 <= 1e19);
        vm.assume(price2 >= 1e9 && price2 <= 1e19);
        vm.assume(price3 >= 1e9 && price3 <= 1e19);
        // Bound deviationBps to reasonable values (10% to 90%)
        vm.assume(deviationBps >= 1000 && deviationBps <= 9000);

        uint256[] memory prices = new uint256[](3);
        prices[0] = price1;
        prices[1] = price2;
        prices[2] = price3;
        bytes memory params = encodeDeviationParams(deviationBps, false);

        // Should not revert with valid inputs
        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Basic sanity check: result should be positive
        assertGt(result, 0, "result should be positive");
    }

    function testFuzz_givenThreePricesWithStrictMode_getAveragePriceExcludingDeviations(
        uint64 price1,
        uint64 price2,
        uint64 price3,
        uint16 deviationBps
    ) public view {
        // Bound prices to a clustered range to ensure at least 2 are non-deviating
        // All prices within 10% of each other = at least 2 will be included
        uint256 basePrice = 1000e18;
        vm.assume(price1 >= 1e8 && price1 <= 1e17); // Allow some variation
        vm.assume(price2 >= 1e8 && price2 <= 1e17);
        vm.assume(price3 >= 1e8 && price3 <= 1e17);

        // Construct prices clustered around basePrice (within 5%)
        // This ensures at least 2/3 will be included with 10% deviation
        uint256[] memory prices = new uint256[](3);
        prices[0] = basePrice + uint256(price1); // 1000e18 to 1001e18 range
        prices[1] = basePrice + uint256(price2);
        prices[2] = basePrice + uint256(price3);

        // Bound deviationBps to reasonable values (10% to 90%)
        vm.assume(deviationBps >= 1000 && deviationBps <= 9000);

        bytes memory params = encodeDeviationParams(deviationBps, true); // strict mode

        // Should not revert with at least 2 clustered prices
        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Basic sanity check: result should be positive
        assertGt(result, 0, "result should be positive");
    }
}
