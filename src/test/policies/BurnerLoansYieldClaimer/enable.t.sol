// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansYieldClaimer} from "src/policies/BurnerLoansYieldClaimer.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerEnableTest is BurnerLoansYieldClaimerTest {
    function test_givenAdmin_enables() public {
        vm.prank(_emergency);
        claimer.disable("");

        vm.prank(admin);
        claimer.enable("");

        assertTrue(claimer.isEnabled(), "enabled");
    }

    function test_givenCallerWithoutAdminRole_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.prank(_emergency);
        claimer.disable("");

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        claimer.enable("");
    }

    function test_givenAlreadyEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(admin);
        claimer.enable("");
    }

    function test_givenBurnerLoansPolicyInactive_reverts() public {
        vm.startPrank(admin);
        claimer.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(target));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidBurnerLoans.selector,
                address(target)
            )
        );
        claimer.enable("");
        vm.stopPrank();
    }

    function test_givenNeverEnabled_whenReEnableCalled_reverts() public {
        BurnerLoansYieldClaimer deployed = new BurnerLoansYieldClaimer(
            kernel,
            address(target),
            _EXECUTION_GAS_LIMIT
        );
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(admin);
        deployed.reEnable();
    }
}
