// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

// Interfaces
import {ISimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";

// Libraries
import {FullMath} from "libraries/FullMath.sol";

/// @title Tests for getAveragePriceExcludingDeviations function
/// @notice Tests the deviation-based price aggregation strategy that excludes outliers
contract SimplePriceFeedStrategyGetAveragePriceExcludingDeviationsTest is
    SimplePriceFeedStrategyBase
{
    // =========  TESTS - AVERAGE PRICE EXCLUDING DEVIATIONS ========= //

    // ============================================================================
    // INPUT VALIDATION TESTS (Configuration Issues - always revert)
    // ============================================================================
    //
    // given input array has less than 3 elements
    //   [X] it reverts with PriceCountInvalid
    //

    function test_givenInputArrayLengthZero_reverts() public {
        uint256[] memory prices = new uint256[](0);
        bytes memory params = _encodeDeviationParams(1000, false);

        _expectRevertPriceCount(0, 3);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenInputArrayLengthOne_reverts() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1000e18;
        bytes memory params = _encodeDeviationParams(1000, false);

        _expectRevertPriceCount(1, 3);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenInputArrayLengthTwo_reverts() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        bytes memory params = _encodeDeviationParams(1000, false);

        _expectRevertPriceCount(2, 3);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenInputArrayLengthLessThanThree_fuzz_reverts(
        uint8 length,
        uint256 price1,
        uint256 price2
    ) public {
        vm.assume(length < 3);
        uint256[] memory prices = new uint256[](length);
        if (length > 0) prices[0] = price1;
        if (length > 1) prices[1] = price2;
        bytes memory params = _encodeDeviationParams(1000, false);

        _expectRevertPriceCount(length, 3);
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

    function test_givenParamsEmpty_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = "";

        _expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenParamsLengthOne_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = hex"01";

        _expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenParamsLengthThirtyTwo_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = hex"0000000000000000000000000000000000000000000000000000000000000001";

        _expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenParamsLengthNinetySix_reverts() public {
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

        _expectRevertParams(paramsExtended);
        strategy.getAveragePriceExcludingDeviations(prices, paramsExtended);
    }

    function test_givenDeviationBpsZero_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = _encodeDeviationParams(0, false);

        _expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenDeviationBpsEqualsMax_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = _encodeDeviationParams(10000, false);

        _expectRevertParams(params);
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

    function test_givenAllPricesZero_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 0;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(1000, false);

        _expectRevertPriceCount(0, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenThreePricesTwoZeros_givenFlagFalse() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 0;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(1000, false);

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Expected: 1000e18 (only non-zero price)
        assertEq(result, 1000e18, "should return single non-zero price");
    }

    function test_givenThreePricesTwoZeros_givenFlagTrue_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 0;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(1000, true);

        _expectRevertPriceCount(1, 2);
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

    function test_givenTwoNonZeroPrices_givenNoneDeviating() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(1000, false); // 10% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // average = (1000e18 + 1050e18) / 2 = 1025e18
        // Neither deviates from 1025e18 by more than 10%
        assertEq(result, 1025e18, "should return average of non-deviating prices");
    }

    function test_givenTwoNonZeroPrices_givenBothDeviating_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1500e18;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(500, false); // 5% deviation

        _expectRevertPriceCount(0, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenTwoNonZeroPrices_givenOneDeviating_givenFlagFalse() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1500e18; // ~40% deviation from average of 1250e18
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(3000, false); // 30% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // average = (1000e18 + 1500e18) / 2 = 1250e18
        // 1000e18: |1000 - 1250| / 1250 = 20% < 30% -> Include
        // 1500e18: |1500 - 1250| / 1250 = 20% < 30% -> Include
        // Both included, return average
        assertEq(result, 1250e18, "should return average of both prices");
    }

    function test_givenTwoNonZeroPrices_wideDeviation_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1500e18; // 40% deviation from average of 1250e18
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(1500, false); // 15% deviation

        // average = (1000e18 + 1500e18) / 2 = 1250e18
        // 1000e18: |1000 - 1250| / 1250 = 20% > 15% -> Exclude
        // 1500e18: |1500 - 1250| / 1250 = 20% > 15% -> Exclude
        // Both excluded -> revert (no data)
        _expectRevertPriceCount(0, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenTwoNonZeroPrices_strictDeviation() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1150e18;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(2000, false); // 20% deviation

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

    function test_givenThreePricesNoneDeviating() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = _encodeDeviationParams(2000, false); // 20% deviation

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

    function test_givenThreePricesOneDeviating() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 5000e18; // Significant outlier
        bytes memory params = _encodeDeviationParams(1000, false); // 10% deviation

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

    function test_givenFivePricesWithOutliers() public view {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        prices[3] = 950e18;
        prices[4] = 5000e18; // Outlier
        bytes memory params = _encodeDeviationParams(1000, false); // 10% deviation

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

    function test_givenOneRemainsAfterExclusion_givenFlagFalse() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 3000e18;
        bytes memory params = _encodeDeviationParams(100, false); // 1% deviation - tight

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

    function test_givenOneRemainsAfterExclusion_givenFlagTrue_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 3000e18;
        bytes memory params = _encodeDeviationParams(100, true); // 1% deviation, strict mode

        _expectRevertPriceCount(1, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    // ============================================================================
    // EDGE CASE TESTS
    // ============================================================================

    // Note: The median price never deviates from itself (0% deviation), so it's
    // not possible for ALL prices to deviate when using median as benchmark.
    // This test verifies the strict mode behavior with tight deviation threshold.

    function test_givenTightDeviationOnlyMedianRemains_givenFlagTrue_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 3000e18;
        bytes memory params = _encodeDeviationParams(100, true); // 1% deviation, strict mode

        // Sorted: [1000e18, 1050e18, 3000e18]
        // Median: 1050e18
        // Deviations from 1050e18:
        //   1000e18: 4.76% > 1% -> Exclude
        //   1050e18: 0% -> Include
        //   3000e18: 185% > 1% -> Exclude
        // Only median remains, flag=true -> revert
        _expectRevertPriceCount(1, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenFourPricesEvenCount_usesMedian() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 900e18;
        prices[1] = 1000e18;
        prices[2] = 1100e18;
        prices[3] = 5000e18;
        bytes memory params = _encodeDeviationParams(1000, false); // 10% deviation

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

    function test_givenThreePricesWithValidDeviation_fuzz(
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
        bytes memory params = _encodeDeviationParams(deviationBps, false);

        // Should not revert with valid inputs
        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Basic sanity check: result should be positive
        assertGt(result, 0, "result should be positive");
    }

    function test_givenThreePricesWithStrictMode_fuzz(
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

        bytes memory params = _encodeDeviationParams(deviationBps, true); // strict mode

        // Should not revert with at least 2 clustered prices
        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Basic sanity check: result should be positive
        assertGt(result, 0, "result should be positive");
    }
}
