// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {BackingOracleTest, ROLESv1} from "./fixtures/BackingOracleTest.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BackingOracleSetConfigOperatorTest is BackingOracleTest {
    // Scenarios: BO-SETCONFIGOPERATOR-01.
    function test_whenAdminRotates(address operator_) public {
        vm.assume(operator_ != address(0));
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(operator_);
        assertEq(
            _oracle.configOperator(),
            operator_,
            "operator selected while paused without metadata probes"
        );
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(address(0));
        assertEq(_oracle.configOperator(), address(0), "zero revokes delegation");
    }

    // Scenarios: BO-SETCONFIGOPERATOR-02.
    function test_whenUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != _ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _oracle.setConfigOperator(address(0));
    }

    // Scenarios: BO-SETCONFIGOPERATOR-03.
    function test_whenUnchanged_reverts() public {
        vm.expectRevert(IConfigOperator.ConfigOperator_Unchanged.selector);
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(address(0));
    }

    // Scenarios: BO-SETCONFIGOPERATOR-04.
    function test_givenInactive_whenRotate_reverts() public givenInactive {
        _expectInactive();
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(_PROPOSER);
    }

    // Scenarios: BO-SETCONFIGOPERATOR-05.
    function test_givenEnabled_whenOperatorWrites() public givenEnabled {
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(_PROPOSER);
        vm.prank(_PROPOSER);
        _oracle.setBacking(110e18);
        assertEq(_oracle.backing(), 110e18, "selected operator has bounded write authority");
    }

    // Scenarios: BO-SETCONFIGOPERATOR-06.
    function test_givenRecovered_whenAdminRotates() public givenRecovered {
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(_PROPOSER);
        vm.prank(_ADMIN);
        _oracle.setBacking(110e18);
        assertEq(
            _oracle.backing(),
            110e18,
            "ADMIN retains direct authority with selected operator"
        );
    }
}
