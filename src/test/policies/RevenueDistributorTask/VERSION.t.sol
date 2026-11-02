// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskVersionTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-VERSION-P01, RDTASK-VERSION-P02, RDTASK-VERSION-P03, RDTASK-VERSION-P04.
    function test_whenAnyCallerReadsVersion_returnsOneZero(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _seedLifecycleRevenue();
        _setRevenuePolicyLifecycle(address(task), active_, enabled_);
        bytes32 beforeState = _revenueAccountingDigest();
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.prank(caller_);
        (uint8 major, uint8 minor) = task.VERSION();

        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
        assertEq(_revenueAccountingDigest(), beforeState, "Metadata read preserves accounting");
        assertEq(task.isEnabled(), enabled_, "Metadata read preserves enabled state");
        assertEq(task.lastTransitionAt(), beforeAt, "Metadata read preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Metadata read emits no logs");
    }

    // Scenarios: RDTASK-VERSION-P01, RDTASK-VERSION-P02, RDTASK-VERSION-P03, RDTASK-VERSION-P04.
    function test_whenAnyCallerReadsVersion_returnsOneZeroLifecycleSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenAnyCallerReadsVersion_returnsOneZero(address(0), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore active enabled seed");
        test_whenAnyCallerReadsVersion_returnsOneZero(address(0), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore active disabled seed");
        test_whenAnyCallerReadsVersion_returnsOneZero(address(0), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled seed");
        test_whenAnyCallerReadsVersion_returnsOneZero(address(0), false, false);
    }
}
