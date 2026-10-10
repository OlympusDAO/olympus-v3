// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansYieldClaimer} from "src/policies/BurnerLoansYieldClaimer.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerEnableTest is BurnerLoansYieldClaimerTest {
    uint48 internal constant _TRANSITION_TIME = 2 days;

    // Scenarios: BLYC-ENABLE-P01.
    function test_givenDisabled_whenAdminEnables_preservesConfiguration(
        bytes calldata data_,
        bool active_
    ) public {
        address[] memory assets = new address[](2);
        assets[0] = address(0xA11CE);
        assets[1] = address(0xB0B);
        target.setAssets(assets);
        vm.prank(admin);
        claimer.setNextAssetIndex(1);
        _setClaimerLifecycle(active_, false);
        uint32 executionLimit = claimer.executionGasLimit();
        uint32 threshold = claimer.minimumGasToAttempt();
        uint32 reserve = claimer.gasReserve();
        uint256 cursor = claimer.nextAssetIndex();
        uint48 transitionTime = _TRANSITION_TIME;
        vm.warp(transitionTime);

        vm.expectEmit(false, false, false, false, address(claimer));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(claimer));
        emit IEnablerV2.Transition(admin, true, data_, transitionTime);
        vm.prank(admin);
        claimer.enable(data_);

        assertTrue(claimer.isEnabled(), "enabled");
        assertEq(claimer.lastTransitionAt(), transitionTime, "enable records timestamp");
        assertEq(claimer.executionGasLimit(), executionLimit, "execution limit preserved");
        assertEq(claimer.minimumGasToAttempt(), threshold, "threshold preserved");
        assertEq(claimer.gasReserve(), reserve, "reserve preserved");
        assertEq(claimer.nextAssetIndex(), cursor, "cursor preserved");
    }

    // Scenarios: BLYC-ENABLE-P02.
    function test_givenNeverEnabled_whenAdminEnables(bytes calldata data_, bool active_) public {
        BurnerLoansYieldClaimer fresh = new BurnerLoansYieldClaimer(
            kernel,
            address(target),
            _EXECUTION_GAS_LIMIT
        );
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(fresh));
        }
        uint48 transitionTime = _TRANSITION_TIME;
        vm.warp(transitionTime);

        vm.expectEmit(false, false, false, false, address(fresh));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(fresh));
        emit IEnablerV2.Transition(admin, true, data_, transitionTime);
        vm.prank(admin);
        fresh.enable(data_);

        assertTrue(fresh.isEnabled(), "fresh claimer enabled");
        assertEq(fresh.lastTransitionAt(), transitionTime, "first transition timestamp recorded");
    }

    // Scenarios: BLYC-ENABLE-A01.
    function test_givenDisabled_whenCallerWithoutAdminRoleEnables_reverts(
        address caller_,
        bytes calldata data_,
        bool active_
    ) public {
        vm.assume(caller_ != admin);
        _setClaimerLifecycle(active_, false);
        uint48 transitionAt = claimer.lastTransitionAt();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        claimer.enable(data_);

        assertFalse(claimer.isEnabled(), "unauthorized enable preserves disabled state");
        assertEq(claimer.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    // Scenarios: BLYC-ENABLE-I01.
    function test_givenEnabled_whenEnableCalled_revertsBeforeOtherChecks(
        address caller_,
        bytes calldata data_,
        bool taskActive_,
        bool targetActive_
    ) public {
        _setTargetLifecycle(targetActive_, true);
        if (!taskActive_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(claimer));
        }

        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        claimer.enable(data_);

        assertTrue(claimer.isEnabled(), "failed enable preserves enabled state");
    }

    // Scenarios: BLYC-ENABLE-I02.
    function test_givenBurnerLoansPolicyInactive_whenAdminEnables_reverts(
        bytes calldata data_,
        bool taskActive_
    ) public {
        _setClaimerLifecycle(taskActive_, false);
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(target));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidBurnerLoans.selector,
                address(target)
            )
        );
        vm.prank(admin);
        claimer.enable(data_);

        assertFalse(claimer.isEnabled(), "claimer remains disabled");
    }
}
