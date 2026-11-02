// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

contract BurnerLoansRiskSetConfigOperatorIntegrationTest is BurnerLoansModularTest {
    // Scenarios: BLRISK-CONFIGURATOR-A01.
    function test_givenCoreWithoutAdmin_whenRiskOperatorIsChanged_reverts() public {
        vm.prank(address(_core));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        _risk.setConfigOperator(_recipient);
    }

    // Scenarios: BLRISK-CONFIGURATOR-A03.
    function test_whenNonAdminChangesRiskOperator_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        _risk.setConfigOperator(_recipient);
    }
}
