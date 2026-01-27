// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {SimplePriceFeedStrategyBase} from "./SimplePriceFeedStrategyBase.t.sol";

// Interfaces
import {ISimplePriceFeedStrategy} from "modules/PRICE/submodules/strategies/ISimplePriceFeedStrategy.sol";

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
    // given deviationBps is > 0 and < 10000
    //   [X] it returns the average of the prices

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

    function test_givenDeviationBpsGreaterThanZeroAndLessThanMax_fuzz(
        uint16 deviationBps_
    ) public view {
        deviationBps_ = uint16(bound(deviationBps_, 1, 9999));

        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1000e18;
        prices[2] = 1000e18;
        bytes memory params = _encodeDeviationParams(deviationBps_, false);

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);
        assertEq(result, 1000e18, "should return average of prices");
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
    //  given revertOnInsufficientCount is false
    //   given both prices deviate from average
    //    [X] it reverts with PriceCountInvalid (no data)
    //   given both prices within deviation threshold
    //    [X] it returns the average of both prices
    //  given revertOnInsufficientCount is true
    //   given both prices deviate from average
    //    [X] it reverts with PriceCountInvalid (no data)
    //   given both prices within deviation threshold
    //    [X] it returns the average of both prices

    function test_givenTwoNonZeroPrices_givenBothDeviating_reverts(uint8 index_) public {
        index_ = uint8(bound(index_, 0, 1));

        uint256[] memory prices = new uint256[](3);
        prices[0] = index_ == 0 ? 1000e18 : 1500e18;
        prices[1] = index_ == 0 ? 1500e18 : 1000e18;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(500, false); // 5% deviation

        // Non-zero prices: [1000e18, 1500e18]
        // Average (benchmark): (1000e18 + 1500e18) / 2 = 1250e18
        // Deviations from 1250e18:
        //   1000e18: |1000 - 1250| / 1250 = 20% > 5% -> Exclude
        //   1500e18: |1500 - 1250| / 1250 = 20% > 5% -> Exclude
        // Result: 0 prices remain -> revert with PriceCountInvalid(0, 2)
        _expectRevertPriceCount(0, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenTwoNonZeroPrices_givenNoneDeviating(uint8 index_) public view {
        index_ = uint8(bound(index_, 0, 1));

        uint256[] memory prices = new uint256[](3);
        prices[0] = index_ == 0 ? 1000e18 : 1050e18;
        prices[1] = index_ == 0 ? 1050e18 : 1000e18;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(1000, false); // 10% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Non-zero prices: [1000e18, 1050e18]
        // Average (benchmark): (1000e18 + 1050e18) / 2 = 1025e18
        // Deviations from 1025e18:
        //   1000e18: |1000 - 1025| / 1025 = 2.44% < 10% -> Include
        //   1050e18: |1050 - 1025| / 1025 = 2.44% < 10% -> Include
        // Result: (1000e18 + 1050e18) / 2 = 1025e18
        assertEq(result, 1025e18, "should return average of non-deviating prices");
    }

    function test_givenTwoNonZeroPrices_givenStrictMode_givenBothDeviating_reverts(
        uint8 index_
    ) public {
        index_ = uint8(bound(index_, 0, 1));

        uint256[] memory prices = new uint256[](3);
        prices[0] = index_ == 0 ? 1000e18 : 1500e18;
        prices[1] = index_ == 0 ? 1500e18 : 1000e18;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(500, true); // 5% deviation

        // Non-zero prices: [1000e18, 1500e18]
        // Average (benchmark): (1000e18 + 1500e18) / 2 = 1250e18
        // Deviations from 1250e18:
        //   1000e18: |1000 - 1250| / 1250 = 20% > 5% -> Exclude
        //   1500e18: |1500 - 1250| / 1250 = 20% > 5% -> Exclude
        // Result: 0 prices remain -> revert with PriceCountInvalid(0, 2)
        _expectRevertPriceCount(0, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_givenTwoNonZeroPrices_givenStrictMode_givenNoneDeviating(
        uint8 index_
    ) public view {
        index_ = uint8(bound(index_, 0, 1));

        uint256[] memory prices = new uint256[](3);
        prices[0] = index_ == 0 ? 1000e18 : 1050e18;
        prices[1] = index_ == 0 ? 1050e18 : 1000e18;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(1000, true); // 10% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Non-zero prices: [1000e18, 1050e18]
        // Average (benchmark): (1000e18 + 1050e18) / 2 = 1025e18
        // Deviations from 1025e18:
        //   1000e18: |1000 - 1025| / 1025 = 2.44% < 10% -> Include
        //   1050e18: |1050 - 1025| / 1025 = 2.44% < 10% -> Include
        // Result: (1000e18 + 1050e18) / 2 = 1025e18
        assertEq(result, 1025e18, "should return average of non-deviating prices");
    }

    // ============================================================================
    // BASIC FUNCTIONALITY TESTS (Median as Benchmark, 3+ prices)
    // ============================================================================
    //
    // when 3 non-zero prices (after zero filtering, median as benchmark)
    //   when no prices deviate from median
    //     [X] it returns the average of all prices
    //   when one price deviates from median
    //     [X] it returns the average of non-deviating prices
    //   when two prices deviate from median
    //     when best effort mode (revertOnInsufficientCount=false)
    //       [X] it returns the remaining price
    //     when strict mode (revertOnInsufficientCount=true)
    //       [X] it reverts with PriceCountInvalid
    //
    // when 4 non-zero prices (after zero filtering, median as benchmark)
    //   when no prices deviate from median
    //     [X] it returns the average of all prices
    //   when one price deviates from median
    //     [X] it returns the average of non-deviating prices
    //   when two prices deviate from median
    //     [X] it returns the average of non-deviating prices
    //   when three prices deviate from median
    //     [N/A] Mathematically impossible for even count (see note below)
    //   when four prices deviate from median
    //     [X] it reverts with PriceCountInvalid (all deviate)
    //
    // when 5 non-zero prices (after zero filtering, median as benchmark)
    //   when outliers are present
    //     [X] it returns the average of non-deviating prices
    //

    function test_whenThreePrices_whenZeroDeviate(uint8 seed) public view {
        seed = uint8(bound(seed, 0, 3));

        // Permute the order of prices based on seed value
        // Each seed places the zero at a different position
        uint256[] memory prices = new uint256[](4);
        if (seed == 0) {
            prices[0] = 0;
            prices[1] = 1000e18;
            prices[2] = 1050e18;
            prices[3] = 1200e18;
        } else if (seed == 1) {
            prices[0] = 1000e18;
            prices[1] = 0;
            prices[2] = 1050e18;
            prices[3] = 1200e18;
        } else if (seed == 2) {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 0;
            prices[3] = 1200e18;
        } else {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 1200e18;
            prices[3] = 0;
        }
        bytes memory params = _encodeDeviationParams(2000, false); // 20% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Non-zero sorted: [1000e18, 1050e18, 1200e18]
        // Median: 1050e18
        // Deviations from 1050e18:
        //   1000e18: |1000 - 1050| / 1050 = 4.76% < 20% -> Include
        //   1050e18: 0% -> Include
        //   1200e18: |1200 - 1050| / 1050 = 14.29% < 20% -> Include
        // Expected: (1000e18 + 1050e18 + 1200e18) / 3 = 3250e18 / 3 = 1083.33...e18
        // 3250000000000000000000 / 3 = 1083333333333333333333 (truncated)
        uint256 expected = 1083333333333333333333;
        assertEq(result, expected, "should return average of all non-deviating prices");
    }

    function test_whenThreePrices_whenOneDeviate(uint8 seed) public view {
        seed = uint8(bound(seed, 0, 3));

        // Permute the order of prices based on seed value
        // Each seed places the zero at a different position
        uint256[] memory prices = new uint256[](4);
        if (seed == 0) {
            prices[0] = 0;
            prices[1] = 1000e18;
            prices[2] = 1050e18;
            prices[3] = 5000e18; // Outlier
        } else if (seed == 1) {
            prices[0] = 1000e18;
            prices[1] = 0;
            prices[2] = 1050e18;
            prices[3] = 5000e18;
        } else if (seed == 2) {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 0;
            prices[3] = 5000e18;
        } else {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 5000e18;
            prices[3] = 0;
        }
        bytes memory params = _encodeDeviationParams(1000, false); // 10% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Non-zero sorted: [1000e18, 1050e18, 5000e18]
        // Median: 1050e18
        // Deviations from 1050e18:
        //   1000e18: |1000 - 1050| / 1050 = 4.76% < 10% -> Include
        //   1050e18: 0% -> Include
        //   5000e18: |5000 - 1050| / 1050 = 376% > 10% -> Exclude
        // Expected: (1000e18 + 1050e18) / 2 = 2050e18 / 2 = 1025e18
        uint256 expected = 1025e18;
        assertEq(result, expected, "should return average of non-deviating prices");
    }

    function test_whenThreePrices_whenTwoDeviate_whenBestEffortMode(uint8 seed) public view {
        seed = uint8(bound(seed, 0, 3));

        // Permute the order of prices based on seed value
        // Each seed places the zero at a different position
        uint256[] memory prices = new uint256[](4);
        if (seed == 0) {
            prices[0] = 0;
            prices[1] = 1000e18;
            prices[2] = 1050e18;
            prices[3] = 3000e18;
        } else if (seed == 1) {
            prices[0] = 1000e18;
            prices[1] = 0;
            prices[2] = 1050e18;
            prices[3] = 3000e18;
        } else if (seed == 2) {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 0;
            prices[3] = 3000e18;
        } else {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 3000e18;
            prices[3] = 0;
        }
        bytes memory params = _encodeDeviationParams(100, false); // 1% deviation - tight

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Non-zero sorted: [1000e18, 1050e18, 3000e18]
        // Median: 1050e18
        // Deviations from 1050e18:
        //   1000e18: |1000 - 1050| / 1050 = 4.76% > 1% -> Exclude
        //   1050e18: 0% -> Include
        //   3000e18: |3000 - 1050| / 1050 = 185.71% > 1% -> Exclude
        // Only median remains (1 price)
        // With best effort mode (flag=false), return single remaining price
        // Expected: 1050e18
        uint256 expected = 1050e18;
        assertEq(result, expected, "should return single remaining price");
    }

    function test_whenThreePrices_whenTwoDeviate_whenStrictMode_reverts(uint8 seed) public {
        seed = uint8(bound(seed, 0, 3));

        // Permute the order of prices based on seed value
        // Each seed places the zero at a different position
        uint256[] memory prices = new uint256[](4);
        if (seed == 0) {
            prices[0] = 0;
            prices[1] = 1000e18;
            prices[2] = 1050e18;
            prices[3] = 3000e18;
        } else if (seed == 1) {
            prices[0] = 1000e18;
            prices[1] = 0;
            prices[2] = 1050e18;
            prices[3] = 3000e18;
        } else if (seed == 2) {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 0;
            prices[3] = 3000e18;
        } else {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 3000e18;
            prices[3] = 0;
        }
        bytes memory params = _encodeDeviationParams(100, true); // 1% deviation, strict mode

        // Non-zero sorted: [1000e18, 1050e18, 3000e18]
        // Median: 1050e18
        // Deviations from 1050e18:
        //   1000e18: |1000 - 1050| / 1050 = 4.76% > 1% -> Exclude
        //   1050e18: 0% -> Include
        //   3000e18: |3000 - 1050| / 1050 = 185.71% > 1% -> Exclude
        // Only median remains (1 price)
        // With strict mode (flag=true), revert with PriceCountInvalid(1, 2)
        _expectRevertPriceCount(1, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenFourPrices_whenZeroDeviate(uint8 seed) public view {
        seed = uint8(bound(seed, 0, 4));

        // Permute the order of prices based on seed value
        // Each seed places the zero at a different position
        uint256[] memory prices = new uint256[](5);
        if (seed == 0) {
            prices[0] = 0;
            prices[1] = 1000e18;
            prices[2] = 1050e18;
            prices[3] = 1100e18;
            prices[4] = 1150e18;
        } else if (seed == 1) {
            prices[0] = 1000e18;
            prices[1] = 0;
            prices[2] = 1050e18;
            prices[3] = 1100e18;
            prices[4] = 1150e18;
        } else if (seed == 2) {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 0;
            prices[3] = 1100e18;
            prices[4] = 1150e18;
        } else if (seed == 3) {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 1100e18;
            prices[3] = 0;
            prices[4] = 1150e18;
        } else {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 1100e18;
            prices[3] = 1150e18;
            prices[4] = 0;
        }
        bytes memory params = _encodeDeviationParams(2000, false); // 20% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Non-zero sorted: [1000e18, 1050e18, 1100e18, 1150e18]
        // Median (even count): (1050e18 + 1100e18) / 2 = 1075e18
        // Deviations from 1075e18:
        //   1000e18: |1000 - 1075| / 1075 = 6.98% < 20% -> Include
        //   1050e18: |1050 - 1075| / 1075 = 2.33% < 20% -> Include
        //   1100e18: |1100 - 1075| / 1075 = 2.33% < 20% -> Include
        //   1150e18: |1150 - 1075| / 1075 = 6.98% < 20% -> Include
        // Expected: (1000e18 + 1050e18 + 1100e18 + 1150e18) / 4 = 4300e18 / 4 = 1075e18
        uint256 expected = 1075e18;
        assertEq(result, expected, "should return average of all non-deviating prices");
    }

    function test_whenFourPrices_whenOneDeviate(uint8 seed) public view {
        seed = uint8(bound(seed, 0, 4));

        // Permute the order of prices based on seed value
        // Each seed places the zero at a different position
        uint256[] memory prices = new uint256[](5);
        if (seed == 0) {
            prices[0] = 0;
            prices[1] = 1000e18;
            prices[2] = 1050e18;
            prices[3] = 1100e18;
            prices[4] = 5000e18; // Outlier
        } else if (seed == 1) {
            prices[0] = 1000e18;
            prices[1] = 0;
            prices[2] = 1050e18;
            prices[3] = 1100e18;
            prices[4] = 5000e18;
        } else if (seed == 2) {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 0;
            prices[3] = 1100e18;
            prices[4] = 5000e18;
        } else if (seed == 3) {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 1100e18;
            prices[3] = 0;
            prices[4] = 5000e18;
        } else {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 1100e18;
            prices[3] = 5000e18;
            prices[4] = 0;
        }
        bytes memory params = _encodeDeviationParams(1000, false); // 10% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Non-zero sorted: [1000e18, 1050e18, 1100e18, 5000e18]
        // Median (even count): (1050e18 + 1100e18) / 2 = 1075e18
        // Deviations from 1075e18:
        //   1000e18: |1000 - 1075| / 1075 = 6.98% < 10% -> Include
        //   1050e18: |1050 - 1075| / 1075 = 2.33% < 10% -> Include
        //   1100e18: |1100 - 1075| / 1075 = 2.33% < 10% -> Include
        //   5000e18: |5000 - 1075| / 1075 = 365% > 10% -> Exclude
        // Expected: (1000e18 + 1050e18 + 1100e18) / 3 = 3150e18 / 3 = 1050e18
        uint256 expected = 1050e18;
        assertEq(result, expected, "should return average excluding outlier");
    }

    function test_whenFourPrices_whenTwoDeviate(uint8 seed) public view {
        seed = uint8(bound(seed, 0, 4));

        // Permute the order of prices based on seed value
        // Each seed places the zero at a different position
        uint256[] memory prices = new uint256[](5);
        if (seed == 0) {
            prices[0] = 0;
            prices[1] = 900e18;
            prices[2] = 1075e18;
            prices[3] = 1100e18;
            prices[4] = 5000e18; // Outlier
        } else if (seed == 1) {
            prices[0] = 900e18;
            prices[1] = 0;
            prices[2] = 1075e18;
            prices[3] = 1100e18;
            prices[4] = 5000e18;
        } else if (seed == 2) {
            prices[0] = 900e18;
            prices[1] = 1075e18;
            prices[2] = 0;
            prices[3] = 1100e18;
            prices[4] = 5000e18;
        } else if (seed == 3) {
            prices[0] = 900e18;
            prices[1] = 1075e18;
            prices[2] = 1100e18;
            prices[3] = 0;
            prices[4] = 5000e18;
        } else {
            prices[0] = 900e18;
            prices[1] = 1075e18;
            prices[2] = 1100e18;
            prices[3] = 5000e18;
            prices[4] = 0;
        }
        bytes memory params = _encodeDeviationParams(500, false); // 5% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Non-zero sorted: [900e18, 1075e18, 1100e18, 5000e18]
        // Median (even count): (1075e18 + 1100e18) / 2 = 1087.5e18
        // Deviations from 1087.5e18:
        //   900e18: |1087.5 - 900| / 1087.5 = 17.24% > 5% -> Exclude
        //   1075e18: |1087.5 - 1075| / 1087.5 = 1.15% < 5% -> Include
        //   1100e18: |1100 - 1087.5| / 1087.5 = 1.15% < 5% -> Include
        //   5000e18: |5000 - 1087.5| / 1087.5 = 360% > 5% -> Exclude
        // Expected: (1075e18 + 1100e18) / 2 = 2175e18 / 2 = 1087.5e18
        uint256 expected = 1087.5e18;
        assertEq(result, expected, "should return average of 2 remaining prices");
    }

    // Note: For even count (4 prices), the median is the average of the two middle
    // values. Due to this mathematical property, both middle values are always
    // equidistant from the median, meaning they either both deviate or both
    // remain. Therefore, "exactly 3 deviating" (leaving 1 remaining) is not
    // possible for even count with median as benchmark.
    //
    // The possible outcomes for 4 prices are:
    //   - 0 deviate (4 remain) ✅ test_whenFourPrices_whenZeroDeviate
    //   - 1 deviates (3 remain) ✅ test_whenFourPrices_whenOneDeviate
    //   - 2 deviate (2 remain) ✅ test_whenFourPrices_whenTwoDeviate_whenTwoRemain
    //   - 4 deviate (0 remain) ✅ test_whenFourPrices_whenAllDeviate_reverts
    //
    // The "1 remaining" case (3 deviating) is only possible with odd counts like
    // 3 prices, where the median is one of the actual values and always included.
    // See test_whenThreePrices_whenTwoDeviate_whenBestEffortMode for the 3-price case.

    function test_whenFourPrices_whenAllDeviate_reverts(uint8 seed) public {
        seed = uint8(bound(seed, 0, 4));

        // Permute the order of prices based on seed value
        // Each seed places the zero at a different position
        uint256[] memory prices = new uint256[](5);
        if (seed == 0) {
            prices[0] = 0;
            prices[1] = 100e18;
            prices[2] = 896e18;
            prices[3] = 1104e18;
            prices[4] = 5000e18;
        } else if (seed == 1) {
            prices[0] = 100e18;
            prices[1] = 0;
            prices[2] = 896e18;
            prices[3] = 1104e18;
            prices[4] = 5000e18;
        } else if (seed == 2) {
            prices[0] = 100e18;
            prices[1] = 896e18;
            prices[2] = 0;
            prices[3] = 1104e18;
            prices[4] = 5000e18;
        } else if (seed == 3) {
            prices[0] = 100e18;
            prices[1] = 896e18;
            prices[2] = 1104e18;
            prices[3] = 0;
            prices[4] = 5000e18;
        } else {
            prices[0] = 100e18;
            prices[1] = 896e18;
            prices[2] = 1104e18;
            prices[3] = 5000e18;
            prices[4] = 0;
        }
        bytes memory params = _encodeDeviationParams(1000, false); // 10% deviation

        // Non-zero sorted: [100e18, 896e18, 1104e18, 5000e18]
        // Median (even count): (896e18 + 1104e18) / 2 = 1000e18
        // Deviations from 1000e18:
        //   100e18: |100 - 1000| / 1000 = 90% > 10% -> Exclude
        //   896e18: |1000 - 896| / 1000 = 10.4% > 10% -> Exclude
        //   1104e18: |1104 - 1000| / 1000 = 10.4% > 10% -> Exclude
        //   5000e18: |5000 - 1000| / 1000 = 400% > 10% -> Exclude
        // All 4 non-zero prices deviate from median -> revert with PriceCountInvalid(0, 2)
        _expectRevertPriceCount(0, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenFivePrices_whenOutliersExcluded(uint8 seed) public view {
        seed = uint8(bound(seed, 0, 5));

        // Permute the order of prices based on seed value
        // Each seed places the zero at a different position
        uint256[] memory prices = new uint256[](6);
        if (seed == 0) {
            prices[0] = 0;
            prices[1] = 1000e18;
            prices[2] = 1050e18;
            prices[3] = 1200e18;
            prices[4] = 950e18;
            prices[5] = 5000e18; // Outlier
        } else if (seed == 1) {
            prices[0] = 1000e18;
            prices[1] = 0;
            prices[2] = 1050e18;
            prices[3] = 1200e18;
            prices[4] = 950e18;
            prices[5] = 5000e18;
        } else if (seed == 2) {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 0;
            prices[3] = 1200e18;
            prices[4] = 950e18;
            prices[5] = 5000e18;
        } else if (seed == 3) {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 1200e18;
            prices[3] = 0;
            prices[4] = 950e18;
            prices[5] = 5000e18;
        } else if (seed == 4) {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 1200e18;
            prices[3] = 950e18;
            prices[4] = 0;
            prices[5] = 5000e18;
        } else {
            prices[0] = 1000e18;
            prices[1] = 1050e18;
            prices[2] = 1200e18;
            prices[3] = 950e18;
            prices[4] = 5000e18;
            prices[5] = 0;
        }
        bytes memory params = _encodeDeviationParams(1000, false); // 10% deviation

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Non-zero sorted: [950e18, 1000e18, 1050e18, 1200e18, 5000e18]
        // Median: 1050e18
        // Deviations from 1050e18:
        //   950e18: |950 - 1050| / 1050 = 9.52% < 10% -> Include
        //   1000e18: |1000 - 1050| / 1050 = 4.76% < 10% -> Include
        //   1050e18: 0% -> Include
        //   1200e18: |1200 - 1050| / 1050 = 14.29% > 10% -> Exclude
        //   5000e18: |5000 - 1050| / 1050 = 376% > 10% -> Exclude
        // Expected: (950e18 + 1000e18 + 1050e18) / 3 = 3000e18 / 3 = 1000e18
        uint256 expected = 1000e18;
        assertEq(result, expected, "should return average excluding outliers");
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
