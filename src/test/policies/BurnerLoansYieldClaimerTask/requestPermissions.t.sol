// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";
import {Permissions} from "src/Kernel.sol";

contract BurnerLoansYieldClaimerTaskRequestPermissionsTest is BurnerLoansYieldClaimerTaskTest {
    // Scenarios: BLYC-PERMISSIONS-P01.
    function test_whenAnyCallerRequestsPermissions_returnsEmpty(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setClaimerLifecycle(active_, enabled_);

        vm.prank(caller_);
        Permissions[] memory permissions = claimer.requestPermissions();

        assertEq(permissions.length, 0, "claimer requests no module permissions");
    }
}
