// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";

contract RevenueDistributorConfigTimelockVersionTest is RevenueDistributorConfigTimelockTest {
    // Scenarios: RDCT-VERSION-P01
    function testFuzz_whenCalledInAnyLifecycleState_returnsVersion(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        if (!enabled_) _disableTimelock();
        if (!active_) _deactivateTimelock();

        vm.prank(caller_);
        (uint8 major, uint8 minor) = configTimelock.VERSION();

        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }
}
