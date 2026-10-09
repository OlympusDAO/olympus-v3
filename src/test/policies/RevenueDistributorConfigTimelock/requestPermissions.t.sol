// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Permissions} from "src/Kernel.sol";
import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";

contract RevenueDistributorConfigTimelockRequestPermissionsTest is
    RevenueDistributorConfigTimelockTest
{
    // Scenarios: RDCT-PERMS-P01
    function testFuzz_whenCalledInAnyLifecycleState_returnsEmptyPermissions(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        if (!enabled_) _disableTimelock();
        if (!active_) _deactivateTimelock();

        vm.prank(caller_);
        Permissions[] memory permissions = configTimelock.requestPermissions();

        assertEq(permissions.length, 0, "permission count");
    }
}
