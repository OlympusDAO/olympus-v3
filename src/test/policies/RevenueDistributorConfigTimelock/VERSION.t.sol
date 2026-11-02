// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";

contract RevenueDistributorConfigTimelockVersionTest is RevenueDistributorConfigTimelockTest {
    // Scenarios: RDCT-VERSION-P01, RDCT-VERSION-P02, RDCT-VERSION-P03, RDCT-VERSION-P04.
    function test_whenCalledInAnyLifecycleState_returnsVersion(
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
        (uint8 major, uint8 minor) = configTimelock.VERSION();

        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
        assertEq(_revenueAccountingDigest(), beforeState, "Metadata read preserves accounting");
        assertEq(configTimelock.isEnabled(), enabled_, "Metadata read preserves enabled state");
        assertEq(configTimelock.lastTransitionAt(), beforeAt, "Metadata read preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Metadata read emits no logs");
    }

    // Scenarios: RDCT-VERSION-P01, RDCT-VERSION-P02, RDCT-VERSION-P03, RDCT-VERSION-P04.
    function test_whenCalledInAnyLifecycleState_returnsVersionLifecycleSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenCalledInAnyLifecycleState_returnsVersion(address(0), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore active enabled seed");
        test_whenCalledInAnyLifecycleState_returnsVersion(address(0), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore active disabled seed");
        test_whenCalledInAnyLifecycleState_returnsVersion(address(0), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled seed");
        test_whenCalledInAnyLifecycleState_returnsVersion(address(0), false, false);
    }
}
