// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Permissions} from "src/Kernel.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorRequestPermissionsTest is RevenueDistributorTest {
    // Scenarios: RD-PERMS-P01, RD-PERMS-P02, RD-PERMS-P03, RD-PERMS-P04.
    function test_whenPermissionsRequested_returnsEmptyArray(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _seedLifecycleRevenue();
        _setRevenuePolicyLifecycle(address(distributor), active_, enabled_);
        bytes32 beforeState = _revenueAccountingDigest();
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.prank(caller_);
        Permissions[] memory permissions = distributor.requestPermissions();

        assertEq(permissions.length, 0, "RevenueDistributor requests no module permissions");
        assertEq(_revenueAccountingDigest(), beforeState, "Metadata read preserves accounting");
        assertEq(distributor.isEnabled(), enabled_, "Metadata read preserves enabled state");
        assertEq(distributor.lastTransitionAt(), beforeAt, "Metadata read preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Metadata read emits no logs");
    }

    // Scenarios: RD-PERMS-P01, RD-PERMS-P02, RD-PERMS-P03, RD-PERMS-P04.
    function test_whenPermissionsRequested_returnsEmptyArrayLifecycleSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenPermissionsRequested_returnsEmptyArray(address(0), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore active enabled seed");
        test_whenPermissionsRequested_returnsEmptyArray(address(0), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore active disabled seed");
        test_whenPermissionsRequested_returnsEmptyArray(address(0), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled seed");
        test_whenPermissionsRequested_returnsEmptyArray(address(0), false, false);
    }
}
