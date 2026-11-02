// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansYieldClaimerTask} from "src/policies/burnerloans/BurnerLoansYieldClaimerTask.sol";

contract BurnerLoansYieldClaimerTaskEnableTest is BurnerLoansYieldClaimerTaskTest {
    // Scenarios: BLYC-ENABLE-A01.
    function test_givenDisabled_whenAdminEnables(address caller_) public {
        _grantClaimerAdmin(caller_, 0);
        _setClaimerLifecycle(true, false);
        vm.warp(2 days);
        bytes32 settings = _settingsDigest();
        _expectTransition(caller_, true);
        vm.prank(caller_);
        claimer.enable("");
        _assertTransition(true, settings);
    }

    // Scenarios: BLYC-ENABLE-A02, BLYC-ENABLE-I03.
    function test_givenUnauthorizedCaller_whenEnabled_reverts(
        address caller_,
        bytes calldata data_
    ) public {
        vm.assume(caller_ != admin);
        _setClaimerLifecycle(true, false);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        claimer.enable(data_);
        assertFalse(claimer.isEnabled(), "Authorization failure preserves local state");
    }

    // Scenarios: BLYC-ENABLE-L01, BLYC-ENABLE-I02.
    function test_givenEnabled_whenEnabledAgain_reverts(
        address caller_,
        bool active_,
        bytes calldata data_
    ) public {
        _setClaimerLifecycle(active_, true);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        claimer.enable(data_);
        assertTrue(claimer.isEnabled(), "State precedence retains enabled flag");
    }

    // Scenarios: BLYC-ENABLE-I01.
    function test_givenDisabled_whenPayloadIsNonempty_reverts(uint16 length_) public {
        _setClaimerLifecycle(true, false);
        bytes memory data = new bytes(bound(length_, 1, 256));
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(admin);
        claimer.enable(data);
        assertFalse(claimer.isEnabled(), "Payload rejection preserves state");
    }

    // Scenarios: BLYC-ENABLE-I01.
    function test_whenPayloadBoundarySeeds_reverts() public {
        test_givenDisabled_whenPayloadIsNonempty_reverts(1);
        _invalidData(hex"01");
        _invalidData(abi.encode(uint256(0)));
        _invalidData(new bytes(256));
    }

    function _invalidData(bytes memory data_) internal {
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(admin);
        claimer.enable(data_);
    }

    // Scenarios: BLYC-ENABLE-D01, BLYC-ENABLE-D02, BLYC-ENABLE-D03.
    function test_givenUnavailableCore_whenEnabled_reverts(bool active_, bool enabled_) public {
        vm.assume(!active_ || !enabled_);
        _setClaimerLifecycle(true, false);
        _setTargetLifecycle(active_, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(target)
            )
        );
        vm.prank(admin);
        claimer.enable("");
        assertFalse(claimer.isEnabled(), "Unavailable Core prevents activation");
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.ActivatePolicy, address(target));
        }
        if (!enabled_) target.enable("");
        vm.prank(admin);
        claimer.enable("");
        assertTrue(claimer.isEnabled(), "Restored dependency permits retry");
    }

    // Scenarios: BLYC-ENABLE-P01.
    function test_givenSettlementRoleRevoked_whenEnabled_reverts() public {
        _setClaimerLifecycle(true, false);
        vm.prank(admin);
        rolesAdmin.revokeRole(BL_YIELD_CLAIMER_ROLE, address(claimer));
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_YIELD_CLAIMER_ROLE)
        );
        vm.prank(admin);
        claimer.enable("");
        assertFalse(claimer.isEnabled(), "Task must hold its own settlement authority");
    }

    // Scenarios: BLYC-ENABLE-D04.
    function test_givenCoreMigrated_whenEnabled_reverts() public {
        _setClaimerLifecycle(true, false);
        Kernel replacement = new Kernel();
        vm.prank(address(kernel));
        target.changeKernel(replacement);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(target),
                address(kernel),
                address(replacement)
            )
        );
        vm.prank(admin);
        claimer.enable("");
        assertFalse(claimer.isEnabled(), "Binding drift prevents activation");
    }

    // Scenarios: BLYC-ENABLE-L02.
    function test_givenInactiveTask_whenEnabled_reverts() public {
        _setClaimerLifecycle(false, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(claimer)
            )
        );
        vm.prank(admin);
        claimer.enable("");
    }

    // Scenarios: BLYC-ENABLE-L03.
    function test_givenNeverActivated_whenEnabled_reverts(address caller_) public {
        BurnerLoansYieldClaimerTask fresh = new BurnerLoansYieldClaimerTask(
            kernel,
            address(target),
            1
        );
        // No cached ROLES means the reached external getter has no ABI return value.
        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        fresh.enable("");
        assertFalse(fresh.isEnabled(), "Fresh policy remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "No transition history");
    }
}
