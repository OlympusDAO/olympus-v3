// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskVersionTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-VERSION-P01.
    function test_whenAnyCallerReadsVersion_returnsOneZero(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        if (!enabled_) _disableTask("");
        if (!active_) _deactivateTask();

        vm.prank(caller_);
        (uint8 major, uint8 minor) = task.VERSION();

        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }
}
