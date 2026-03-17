// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";

import {Deviation} from "libraries/Deviation.sol";

contract DeviationTest is Test {
    uint256 internal _benchmark;
    uint256 internal _value;
    uint256 internal _deviationBps;
    uint256 internal _deviationMax;

    modifier givenBenchmarkWithSmallDeviationBps() {
        _benchmark = 100_000_000;
        _deviationBps = 1;
        _deviationMax = 10_000;
        _;
    }

    modifier givenBenchmarkWithSmallDeviationBpsAndValueOutsideBound() {
        _benchmark = 100_000_000;
        _value = _benchmark + 19_999;
        _deviationBps = 1;
        _deviationMax = 10_000;
        _;
    }

    modifier givenBenchmarkWithLargeDeviationBpsAndValueNearBenchmark() {
        _benchmark = 100_000_000;
        _value = _benchmark + 19_999;
        _deviationBps = 9_999;
        _deviationMax = 10_000;
        _;
    }

    function exposed_isDeviatingWithBpsCheck(
        uint256 value_,
        uint256 benchmark_,
        uint256 deviationBps_,
        uint256 deviationMax_
    ) external pure returns (bool) {
        return Deviation.isDeviatingWithBpsCheck(value_, benchmark_, deviationBps_, deviationMax_);
    }

    function test_givenValueEqualsBenchmark_isDeviating_returnsFalse() public pure {
        uint256 value = 100;
        uint256 benchmark = 100;
        uint256 deviationBps = 100;
        uint256 deviationMax = 10000;
        // deviationBps/deviationMax uses a 1e4 basis-point scale:
        // 100 / 10_000 = 0.01 = 1.00% allowed deviation from benchmark.
        // allowed absolute deviation = benchmark * deviationBps / deviationMax
        // = 100 * 100 / 10_000 = 1.00 (value units).
        // allowed range = benchmark +/- allowed deviation = 100 +/- 1.00 => [99.00, 101.00].
        // With value = 100, diff = |100 - 100| = 0 <= 1.00, so not deviating.
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            false,
            "value == benchmark"
        );
    }

    function test_givenValueAtUpperBound_isDeviating_returnsFalse() public pure {
        uint256 value = 101;
        uint256 benchmark = 100;
        uint256 deviationBps = 100;
        uint256 deviationMax = 10000;

        // value = 101 is at the upper bound of [99.00, 101.00].
        // diff = |101 - 100| = 1 <= 1.00, so not deviating.
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            false,
            "value > benchmark, within bounds"
        );
    }

    function test_givenValueAtLowerBound_isDeviating_returnsFalse() public pure {
        uint256 value = 99;
        uint256 benchmark = 100;
        uint256 deviationBps = 100;
        uint256 deviationMax = 10000;

        // value = 99 is at the lower bound of [99.00, 101.00].
        // diff = |99 - 100| = 1 <= 1.00, so not deviating.
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            false,
            "value < benchmark, within bounds"
        );
    }

    function test_givenValueExceedsUpperBound_isDeviating_returnsTrue() public pure {
        uint256 value = 102;
        uint256 benchmark = 100;
        uint256 deviationBps = 100;
        uint256 deviationMax = 10000;

        // value = 102 exceeds the upper bound (102 > 101.00).
        // diff = |102 - 100| = 2 > 1.00, so deviating.
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            true,
            "value > benchmark, outside bounds"
        );
    }

    function test_givenValueBelowLowerBound_isDeviating_returnsTrue() public pure {
        uint256 value = 98;
        uint256 benchmark = 100;
        uint256 deviationBps = 100;
        uint256 deviationMax = 10000;

        // value = 98 is below the lower bound (98 < 99.00).
        // diff = |98 - 100| = 2 > 1.00, so deviating.
        // deviationMax = 10_000 means "100.00%" basis-point denominator, so
        // deviationBps = 100 is interpreted as exactly 1.00%.
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            true,
            "value < benchmark, outside bounds"
        );
    }

    function test_givenBenchmarkWithSmallDeviationBps_whenValueExceedsBenchmark_thenDeviates()
        public
        givenBenchmarkWithSmallDeviationBpsAndValueOutsideBound
    {
        // benchmark = 100_000_000 (8-decimal integer scale)
        // deviation ratio = deviationBps / deviationMax = 1 / 10_000 = 0.01%
        // allowed absolute deviation = benchmark * deviationBps / deviationMax
        // = 100_000_000 * 1 / 10_000 = 10_000 (same 8-decimal integer scale)
        // upper bound = benchmark + allowed deviation = 100_010_000
        // value = benchmark + 19_999 = 100_019_999 > 100_010_000
        // so value is outside bounds and isDeviating(...) must return true.
        assertEq(
            Deviation.isDeviating(_value, _benchmark, _deviationBps, _deviationMax),
            true,
            "value > benchmark, outside bounds"
        );
    }

    function test_givenBenchmarkWithSmallDeviationBps_whenValueWithinBound_thenNotDeviating(
        uint256 value_
    ) public givenBenchmarkWithSmallDeviationBps {
        _value = bound(value_, _benchmark, _benchmark + 10_000);

        // benchmark = 100_000_000 (8-decimal integer scale)
        // deviation ratio = 1 / 10_000 = 0.01%
        // allowed absolute deviation = 100_000_000 * 1 / 10_000 = 10_000
        // upper bound = benchmark + 10_000 = 100_010_000
        // fuzzed value is constrained to [100_000_000, 100_010_000], so it is in-bounds
        // and isDeviating(...) must return false.

        assertEq(
            Deviation.isDeviating(_value, _benchmark, _deviationBps, _deviationMax),
            false,
            "value > benchmark, inside bounds"
        );
    }

    function test_givenBenchmarkWithSmallDeviationBps_whenValueOutsideBound_thenDeviating(
        uint256 value_
    ) public givenBenchmarkWithSmallDeviationBps {
        _value = bound(value_, _benchmark + 10_001, _benchmark + 50_000);

        // benchmark = 100_000_000 (8-decimal integer scale)
        // deviation ratio = 1 / 10_000 = 0.01%
        // allowed absolute deviation = 100_000_000 * 1 / 10_000 = 10_000
        // upper bound = benchmark + 10_000 = 100_010_000
        // fuzzed value is constrained to [100_010_001, 100_050_000], so it is out-of-bounds
        // and isDeviating(...) must return true.

        assertEq(
            Deviation.isDeviating(_value, _benchmark, _deviationBps, _deviationMax),
            true,
            "value > benchmark, outside bounds"
        );
    }

    function test_givenBenchmarkWithLargeDeviationBps_whenValueNearBenchmark_thenNotDeviating()
        public
        givenBenchmarkWithLargeDeviationBpsAndValueNearBenchmark
    {
        // benchmark = 100_000_000 (8-decimal integer scale)
        // deviation ratio = 9_999 / 10_000 = 99.99%
        // allowed absolute deviation = benchmark * deviationBps / deviationMax
        // = 100_000_000 * 9_999 / 10_000 = 99_990_000
        // upper bound = benchmark + allowed deviation = 199_990_000
        // value = benchmark + 19_999 = 100_019_999 <= 199_990_000
        // so value is within bounds and isDeviating(...) must return false.
        assertEq(
            Deviation.isDeviating(_value, _benchmark, _deviationBps, _deviationMax),
            false,
            "value > benchmark, inside bounds"
        );
    }

    function test_givenDeviationBpsExceedsDeviationMax_whenCheckingWithGuard_thenReverts() public {
        uint256 benchmark = 100_000_000;
        uint256 value = benchmark;
        uint256 deviationMax = 10_000;
        uint256 deviationBps = deviationMax + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                Deviation.Deviation_InvalidDeviationBps.selector,
                deviationBps,
                deviationMax
            )
        );
        this.exposed_isDeviatingWithBpsCheck(value, benchmark, deviationBps, deviationMax);
    }
}
