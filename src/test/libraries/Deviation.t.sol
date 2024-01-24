// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {Deviation} from "libraries/Deviation.sol";

contract DeviationTest is Test {
    function test_isDeviating() public {
        uint256 value = 100;
        uint256 benchmark = 100;
        uint256 deviationBps = 100;
        uint256 deviationMax = 10000;
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            false,
            "value == benchmark"
        );

        value = 101;
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            false,
            "value > benchmark, within bounds"
        );
        value = 99;
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            false,
            "value < benchmark, within bounds"
        );

        value = 102;
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            true,
            "value > benchmark, outside bounds"
        );
        value = 98;
        assertEq(
            Deviation.isDeviating(value, benchmark, deviationBps, deviationMax),
            true,
            "value < benchmark, outside bounds"
        );
    }
}
