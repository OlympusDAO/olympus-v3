// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Permissions} from "src/Kernel.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskRequestPermissionsTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-PERMS-P01, RDTASK-PERMS-P02, RDTASK-PERMS-P03, RDTASK-PERMS-P04.
    function test_whenAnyCallerRequestsPermissions_returnsEmpty(
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
        Permissions[] memory permissions = task.requestPermissions();

        assertEq(permissions.length, 0, "task requests no module permissions");
        assertEq(_revenueAccountingDigest(), beforeState, "Metadata read preserves accounting");
        assertEq(task.isEnabled(), enabled_, "Metadata read preserves enabled state");
        assertEq(task.lastTransitionAt(), beforeAt, "Metadata read preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Metadata read emits no logs");
    }

    // Scenarios: RDTASK-PERMS-P01, RDTASK-PERMS-P02, RDTASK-PERMS-P03, RDTASK-PERMS-P04.
    function test_whenAnyCallerRequestsPermissions_returnsEmptyLifecycleSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenAnyCallerRequestsPermissions_returnsEmpty(address(0), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore active enabled seed");
        test_whenAnyCallerRequestsPermissions_returnsEmpty(address(0), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore active disabled seed");
        test_whenAnyCallerRequestsPermissions_returnsEmpty(address(0), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled seed");
        test_whenAnyCallerRequestsPermissions_returnsEmpty(address(0), false, false);
    }
}
