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
    // when input array has less than 3 elements
    //   [X] it reverts with PriceCountInvalid
    //

    function test_whenInputArrayLengthZero_reverts() public {
        uint256[] memory prices = new uint256[](0);
        bytes memory params = _encodeDeviationParams(1000, false);

        _expectRevertPriceCount(0, 3);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenInputArrayLengthOne_reverts() public {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1000e18;
        bytes memory params = _encodeDeviationParams(1000, false);

        _expectRevertPriceCount(1, 3);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenInputArrayLengthTwo_reverts() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        bytes memory params = _encodeDeviationParams(1000, false);

        _expectRevertPriceCount(2, 3);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenInputArrayLengthLessThanThree_reverts_fuzz(
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
    // when params length is not 64 bytes
    //   [X] it reverts with ParamsInvalid
    //
    // when deviationBps is 0 or >= 10000
    //   [X] it reverts with ParamsInvalid
    //
    // when deviationBps is > 0 and < 10000
    //   [X] it returns the average of the prices

    function test_whenParamsEmpty_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = "";

        _expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenParamsLengthOne_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = hex"01";

        _expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenParamsLengthThirtyTwo_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = hex"0000000000000000000000000000000000000000000000000000000000000001";

        _expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenParamsLengthNinetySix_reverts() public {
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

    function test_whenDeviationBpsZero_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = _encodeDeviationParams(0, false);

        _expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenDeviationBpsEqualsMax_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 1050e18;
        prices[2] = 1200e18;
        bytes memory params = _encodeDeviationParams(10000, false);

        _expectRevertParams(params);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenValidDeviationBps_fuzz(uint16 deviationBps_) public view {
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
    // when all prices are zero
    //   [X] it reverts with PriceCountInvalid
    //
    // when exactly 1 non-zero price (after zero filtering)
    //   when revertOnInsufficientCount is false
    //     [X] it returns the single non-zero price
    //   when revertOnInsufficientCount is true
    //     [X] it reverts with PriceCountInvalid

    function test_whenAllPricesZero_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0;
        prices[1] = 0;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(1000, false);

        _expectRevertPriceCount(0, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenOneNonZeroPrice_strictMode_reverts() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 0;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(1000, true);

        _expectRevertPriceCount(1, 2);
        strategy.getAveragePriceExcludingDeviations(prices, params);
    }

    function test_whenOneNonZeroPrice_bestEffortMode() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000e18;
        prices[1] = 0;
        prices[2] = 0;
        bytes memory params = _encodeDeviationParams(1000, false);

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);

        // Expected: 1000e18 (only non-zero price)
        assertEq(result, 1000e18, "should return single non-zero price");
    }

    // ============================================================================
    // TWO-PRICE FALLBACK TESTS (Average as Benchmark)
    // ============================================================================
    //
    // when exactly 2 non-zero prices (after zero filtering)
    //  when revertOnInsufficientCount is false
    //   when both prices deviate from average
    //    [X] it reverts with PriceCountInvalid (no data)
    //   when both prices within deviation threshold
    //    [X] it returns the average of both prices
    //  when revertOnInsufficientCount is true
    //   when both prices deviate from average
    //    [X] it reverts with PriceCountInvalid (no data)
    //   when both prices within deviation threshold
    //    [X] it returns the average of both prices

    function test_whenTwoNonZeroPrices_bothDeviating_reverts(uint8 index_) public {
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

    function test_whenTwoNonZeroPrices_noneDeviating(uint8 index_) public view {
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

    function test_whenTwoNonZeroPrices_strictMode_bothDeviating_reverts(uint8 index_) public {
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

    function test_whenTwoNonZeroPrices_strictMode_noneDeviating(uint8 index_) public view {
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

    function test_whenThreePrices_zeroDeviating(uint8 seed) public view {
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

    function test_whenThreePrices_oneDeviating(uint8 seed) public view {
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

    function test_whenThreePrices_twoDeviating_bestEffortMode(uint8 seed) public view {
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

    function test_whenThreePrices_twoDeviating_strictMode_reverts(uint8 seed) public {
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

    function test_whenFourPrices_zeroDeviating(uint8 seed) public view {
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

    function test_whenFourPrices_oneDeviating(uint8 seed) public view {
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

    function test_whenFourPrices_twoDeviating(uint8 seed) public view {
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

    function test_whenFourPrices_allDeviating_reverts(uint8 seed) public {
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

    function test_whenFivePrices_outliersExcluded(uint8 seed) public view {
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
    // when random valid inputs with flag=false
    //   [X] it does not revert
    // when random clustered inputs with flag=true
    //   [X] it does not revert
    //
    // ============================================================================

    function test_whenThreePricesDeviating_fuzz(
        uint256 basePrice_,
        uint256 deviationAmount_
    ) public view {
        uint16 deviationBps = 1000; // 10%
        // Base price between 0.5e18 and 1.5e18
        uint256 basePrice = bound(basePrice_, 0.5e18, 1.5e18);
        // Deviation amount between 20% and 100% of base price (ensures deviation detected)
        uint256 deviationAmount = bound(deviationAmount_, basePrice / 5, basePrice);

        uint256[] memory prices = new uint256[](3);
        prices[0] = basePrice;
        prices[1] = basePrice;
        prices[2] = basePrice + deviationAmount; // Deviates from average

        // Expected: average of non-deviating prices = basePrice
        uint256 result = strategy.getAveragePriceExcludingDeviations(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        assertEq(result, basePrice, "should return average of non-deviating prices");
    }

    function test_whenThreePricesNotDeviating_fuzz(
        uint256 basePrice_,
        uint256 smallVariance1_,
        uint256 smallVariance2_
    ) public view {
        uint16 deviationBps = 1000; // 10%
        // Base price between 0.5e18 and 1.5e18
        uint256 basePrice = bound(basePrice_, 0.5e18, 1.5e18);
        // Small variances less than 1% of base price (ensures no deviation)
        uint256 smallVariance1 = bound(smallVariance1_, 0, basePrice / 100);
        uint256 smallVariance2 = bound(smallVariance2_, 0, basePrice / 100);

        uint256[] memory prices = new uint256[](3);
        prices[0] = basePrice;
        prices[1] = basePrice + smallVariance1;
        prices[2] = basePrice + smallVariance2;

        // Expected: average of all three prices (none deviate)
        uint256 expectedAverage = (basePrice +
            (basePrice + smallVariance1) +
            (basePrice + smallVariance2)) / 3;

        uint256 result = strategy.getAveragePriceExcludingDeviations(
            prices,
            _encodeDeviationParams(deviationBps, false)
        );
        assertEq(result, expectedAverage, "should return average of all prices when none deviate");
    }

    function test_whenThreePrices_strictMode_fuzz(
        uint256 basePrice_,
        uint256 smallVariance1_,
        uint256 smallVariance2_
    ) public view {
        uint16 deviationBps = 1000; // 10%
        // Base price between 0.5e18 and 1.5e18
        uint256 basePrice = bound(basePrice_, 0.5e18, 1.5e18);
        // Small variances less than 1% of base price (ensures no deviation)
        uint256 smallVariance1 = bound(smallVariance1_, 0, basePrice / 100);
        uint256 smallVariance2 = bound(smallVariance2_, 0, basePrice / 100);

        uint256[] memory prices = new uint256[](3);
        prices[0] = basePrice;
        prices[1] = basePrice + smallVariance1;
        prices[2] = basePrice + smallVariance2;

        // Expected: average of all three prices (none deviate)
        uint256 expectedAverage = (basePrice +
            (basePrice + smallVariance1) +
            (basePrice + smallVariance2)) / 3;

        bytes memory params = _encodeDeviationParams(deviationBps, true); // strict mode

        uint256 result = strategy.getAveragePriceExcludingDeviations(prices, params);
        assertEq(
            result,
            expectedAverage,
            "should return average of all non-deviating prices in strict mode"
        );
    }
}
