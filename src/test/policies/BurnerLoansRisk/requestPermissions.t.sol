// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {Permissions} from "src/Kernel.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskRequestPermissionsTest is BurnerLoansRiskTest {
    // Scenarios: BLRISK-CONSTRUCTOR-V09.
    function test_givenOperational_whenPermissionsRequested(address caller_) public {
        vm.prank(caller_);
        Permissions[] memory permissions = _risk.requestPermissions();
        assertEq(permissions.length, 0, "Risk requests no module writes");
    }

    // Scenarios: BLRISK-CONSTRUCTOR-V09.
    function test_givenDisabled_whenPermissionsRequested(address caller_) public givenDisabled {
        vm.prank(caller_);
        Permissions[] memory permissions = _risk.requestPermissions();
        assertEq(permissions.length, 0, "Risk requests no module writes");
    }

    // Scenarios: BLRISK-CONSTRUCTOR-V09.
    function test_givenInactive_whenPermissionsRequested(address caller_) public givenInactive {
        vm.prank(caller_);
        Permissions[] memory permissions = _risk.requestPermissions();
        assertEq(permissions.length, 0, "Risk requests no module writes");
    }

    // Scenarios: BLRISK-CONSTRUCTOR-V09.
    function test_givenInactiveAndDisabled_whenPermissionsRequested(
        address caller_
    ) public givenDisabled givenInactive {
        vm.prank(caller_);
        Permissions[] memory permissions = _risk.requestPermissions();
        assertEq(permissions.length, 0, "Risk requests no module writes");
    }
}
