// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorVersionTest is RevenueDistributorTest {
    // Scenarios: RD-VERSION-P01, RD-VERSION-P02, RD-VERSION-P03, RD-VERSION-P04.
    function test_whenVersionRead_returnsVersionOneZero(
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
        (uint8 major, uint8 minor) = distributor.VERSION();

        assertEq(major, 1, "major version is one");
        assertEq(minor, 0, "minor version is zero");
        assertEq(_revenueAccountingDigest(), beforeState, "Metadata read preserves accounting");
        assertEq(distributor.isEnabled(), enabled_, "Metadata read preserves enabled state");
        assertEq(distributor.lastTransitionAt(), beforeAt, "Metadata read preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Metadata read emits no logs");
    }

    // Scenarios: RD-VERSION-P01, RD-VERSION-P02, RD-VERSION-P03, RD-VERSION-P04.
    function test_whenVersionRead_returnsVersionOneZeroLifecycleSeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenVersionRead_returnsVersionOneZero(address(0), true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore active enabled seed");
        test_whenVersionRead_returnsVersionOneZero(address(0), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore active disabled seed");
        test_whenVersionRead_returnsVersionOneZero(address(0), false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled seed");
        test_whenVersionRead_returnsVersionOneZero(address(0), false, false);
    }
}
