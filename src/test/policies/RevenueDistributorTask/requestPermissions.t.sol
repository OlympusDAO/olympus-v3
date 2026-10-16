// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Permissions} from "src/Kernel.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskRequestPermissionsTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-PERMS-P01.
    function test_whenAnyCallerRequestsPermissions_returnsEmpty(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        if (!enabled_) _disableTask("");
        if (!active_) _deactivateTask();

        vm.prank(caller_);
        Permissions[] memory permissions = task.requestPermissions();

        assertEq(permissions.length, 0, "task requests no module permissions");
    }
}
