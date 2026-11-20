// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Contracts
import {PriceCacherTaskLifecycleTest} from "./fixtures/PriceCacherTaskLifecycleTest.sol";
import {Permissions} from "src/Kernel.sol";

contract PriceCacherTaskRequestPermissionsTest is PriceCacherTaskLifecycleTest {
    // Scenarios: PCACHER-PERMISSIONS-P01.
    function test_whenPermissionsRequested(address caller_) public {
        vm.record();
        vm.recordLogs();
        vm.prank(caller_);
        Permissions[] memory permissions = cacher.requestPermissions();
        assertEq(permissions.length, 0, "no module write permissions requested");
        (, bytes32[] memory writes) = vm.accesses(_lifecycleTarget);
        assertEq(writes.length, 0, "permission query writes nothing");
        assertEq(vm.getRecordedLogs().length, 0, "permission query emits nothing");
    }

    // Scenarios: PCACHER-PERMISSIONS-P02.
    function test_givenNeverConfigured_whenPermissionsRequested(address caller_) public {
        _freshSubject(false);
        vm.prank(caller_);
        assertEq(cacher.requestPermissions().length, 0, "no dependency setup or activity required");
    }
}
