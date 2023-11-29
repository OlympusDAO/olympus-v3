// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {Deviation} from "libraries/Deviation.sol";

contract DeviationTest is Test {
    function test_isDeviating() public {
        uint256 value0 = 100;
        uint256 value1 = 100;
        uint256 deviationBps = 100;
        uint256 deviationMax = 10000;
        assertEq(
            Deviation.isDeviating(value0, value1, deviationBps, deviationMax),
            false,
            "value0 == value1"
        );

        value1 = 101;
        assertEq(
            Deviation.isDeviating(value0, value1, deviationBps, deviationMax),
            false,
            "value1 > value0, within bounds"
        );
        assertEq(
            Deviation.isDeviating(value1, value0, deviationBps, deviationMax),
            false,
            "value0 < value1, within bounds"
        );

        value1 = 102;
        assertEq(
            Deviation.isDeviating(value0, value1, deviationBps, deviationMax),
            true,
            "value1 > value0, outside bounds"
        );
        assertEq(
            Deviation.isDeviating(value1, value0, deviationBps, deviationMax),
            true,
            "value0 < value1, outside bounds"
        );

        value1 = 99;
        assertEq(
            Deviation.isDeviating(value0, value1, deviationBps, deviationMax),
            false,
            "value1 < value0, within bounds"
        );
        assertEq(
            Deviation.isDeviating(value1, value0, deviationBps, deviationMax),
            false,
            "value0 > value1, within bounds"
        );

        value1 = 98;
        assertEq(
            Deviation.isDeviating(value0, value1, deviationBps, deviationMax),
            true,
            "value1 < value0, outside bounds"
        );
        assertEq(
            Deviation.isDeviating(value1, value0, deviationBps, deviationMax),
            true,
            "value0 > value1, outside bounds"
        );
    }
}
