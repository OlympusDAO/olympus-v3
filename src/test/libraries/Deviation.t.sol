// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {Deviation} from "libraries/Deviation.sol";

contract DeviationTest is Test {
    function test_isDeviating() public pure {
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

        value = 101;
        // value = 101 is at the upper bound of [99.00, 101.00].
        // diff = |101 - 100| = 1 <= 1.00, so not deviating.
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            false,
            "value > benchmark, within bounds"
        );
        value = 99;
        // value = 99 is at the lower bound of [99.00, 101.00].
        // diff = |99 - 100| = 1 <= 1.00, so not deviating.
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            false,
            "value < benchmark, within bounds"
        );

        value = 102;
        // value = 102 exceeds the upper bound (102 > 101.00).
        // diff = |102 - 100| = 2 > 1.00, so deviating.
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            true,
            "value > benchmark, outside bounds"
        );
        value = 98;
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

    function test_isDeviating_smallDeviationBps() public pure {
        uint256 benchmark = 100_000_000;
        uint256 value = benchmark + 19_999;
        uint256 deviationBps = 1;
        uint256 deviationMax = 10_000;

        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            true,
            "value > benchmark, outside bounds"
        );
    }

    function test_isDeviating_smallDeviationBps_insideBounds_fuzz(uint256 value_) public pure {
        uint256 benchmark = 100_000_000;
        uint256 value = bound(value_, benchmark, benchmark + 10_000);
        uint256 deviationBps = 1;
        uint256 deviationMax = 10_000;

        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            false,
            "value > benchmark, inside bounds"
        );
    }

    function test_isDeviating_smallDeviationBps_outsideBounds_fuzz(uint256 value_) public pure {
        uint256 benchmark = 100_000_000;
        uint256 value = bound(value_, benchmark + 10_001, benchmark + 50_000);
        uint256 deviationBps = 1;
        uint256 deviationMax = 10_000;

        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            true,
            "value > benchmark, outside bounds"
        );
    }

    function test_isDeviating_largeDeviationBps() public pure {
        uint256 benchmark = 100_000_000;
        uint256 value = benchmark + 19_999;
        uint256 deviationBps = 9_999;
        uint256 deviationMax = 10_000;

        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            false,
            "value > benchmark, inside bounds"
        );
    }
}
