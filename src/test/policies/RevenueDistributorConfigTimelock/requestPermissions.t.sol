// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Permissions} from "src/Kernel.sol";
import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";

contract RevenueDistributorConfigTimelockRequestPermissionsTest is
    RevenueDistributorConfigTimelockTest
{
    // Scenarios: RDCT-PERMS-P01, RDCT-PERMS-P02, RDCT-PERMS-P03, RDCT-PERMS-P04.
    function test_whenCalledInAnyLifecycleState_returnsEmptyPermissions(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _seedLifecycleRevenue();
        _setRevenuePolicyLifecycle(address(configTimelock), active_, enabled_);
        bytes32 beforeState = _revenueAccountingDigest();
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.prank(caller_);
        Permissions[] memory permissions = configTimelock.requestPermissions();

        assertEq(permissions.length, 0, "permission count");
        assertEq(_revenueAccountingDigest(), beforeState, "Metadata read preserves accounting");
        assertEq(configTimelock.isEnabled(), enabled_, "Metadata read preserves enabled state");
        assertEq(configTimelock.lastTransitionAt(), beforeAt, "Metadata read preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Metadata read emits no logs");
    }

    // Scenarios: RDCT-PERMS-P01, RDCT-PERMS-P02, RDCT-PERMS-P03, RDCT-PERMS-P04.
    function test_whenCalledInAnyLifecycleState_returnsEmptyPermissionsLifecycleSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenCalledInAnyLifecycleState_returnsEmptyPermissions(address(0), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore active enabled seed");
        test_whenCalledInAnyLifecycleState_returnsEmptyPermissions(address(0), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore active disabled seed");
        test_whenCalledInAnyLifecycleState_returnsEmptyPermissions(address(0), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled seed");
        test_whenCalledInAnyLifecycleState_returnsEmptyPermissions(address(0), false, false);
    }
}
