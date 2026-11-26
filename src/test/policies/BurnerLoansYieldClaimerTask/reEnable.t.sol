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

contract BurnerLoansYieldClaimerTaskReEnableTest is BurnerLoansYieldClaimerTaskTest {
    function _pauseAt(uint48 time_, uint32 period_) internal {
        vm.prank(admin);
        claimer.setGracePeriod(period_);
        vm.warp(time_);
        vm.prank(admin);
        claimer.disable("");
        assertEq(claimer.lastTransitionAt(), time_, "Disable establishes exact L");
    }

    // Scenarios: BLYC-REENABLE-A03, BLYC-REENABLE-A04, BLYC-REENABLE-A05, BLYC-REENABLE-P01.
    function test_givenWithinGrace_whenPermittedCallerReEnables(
        address caller_,
        uint8 roleClass_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        grace_ = _boundUint32(grace_, 1, type(uint32).max);
        last_ = _boundUint48(last_, 1, type(uint48).max - grace_);
        now_ = _boundUint48(now_, last_, last_ + grace_ - 1);
        _pauseAt(last_, grace_);
        vm.warp(now_);
        bytes32 settings = _settingsDigest();
        _expectTransition(caller_, true);
        vm.prank(caller_);
        claimer.reEnable();
        _assertTransition(true, settings);
    }

    // Scenarios: BLYC-REENABLE-P02.
    function test_givenExactDeadline_whenReEnabled(
        address caller_,
        uint8 roleClass_,
        uint48 last_,
        uint32 grace_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        grace_ = _boundUint32(grace_, 1, type(uint32).max);
        last_ = _boundUint48(last_, 1, type(uint48).max - grace_);
        _pauseAt(last_, grace_);
        vm.warp(uint256(last_) + grace_);
        bytes32 settings = _settingsDigest();
        _expectTransition(caller_, true);
        vm.prank(caller_);
        claimer.reEnable();
        _assertTransition(true, settings);
    }

    // Scenarios: BLYC-REENABLE-P01, BLYC-REENABLE-P02, BLYC-REENABLE-A03, BLYC-REENABLE-A04, BLYC-REENABLE-A05.
    function test_whenValidTimeAndRoleBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass) {
            test_givenWithinGrace_whenPermittedCallerReEnables(address(0xBEEF), roleClass, 1, 1, 1);
            vm.revertToState(snapshot);
            test_givenWithinGrace_whenPermittedCallerReEnables(
                address(0xBEEF),
                roleClass,
                type(uint48).max - type(uint32).max,
                type(uint32).max,
                type(uint48).max - 1
            );
            vm.revertToState(snapshot);
            test_givenExactDeadline_whenReEnabled(
                address(0xBEEF),
                roleClass,
                type(uint48).max - 1,
                1
            );
            vm.revertToState(snapshot);
        }
    }

    // Scenarios: BLYC-REENABLE-A01, BLYC-REENABLE-A02.
    function test_givenUnauthorizedCaller_whenReEnabled_reverts(
        address caller_,
        bool expired_
    ) public {
        vm.assume(caller_ != admin && caller_ != burnerLoansAdmin);
        _pauseAt(1000, 1);
        if (expired_) {
            vm.warp(1002);
            target.disable("");
        }
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.reEnable();
        assertFalse(claimer.isEnabled(), "Authorization precedes grace and readiness");
    }

    // Scenarios: BLYC-REENABLE-L01.
    function test_givenEnabled_whenReEnabled_reverts(address caller_, bool active_) public {
        _setClaimerLifecycle(active_, true);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        claimer.reEnable();
    }

    // Scenarios: BLYC-REENABLE-L02, BLYC-REENABLE-L04.
    function test_givenNeverEnabled_whenReEnabled_reverts(address caller_, bool active_) public {
        BurnerLoansYieldClaimerTask fresh = new BurnerLoansYieldClaimerTask(
            kernel,
            address(target),
            1
        );
        if (active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        }
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
        assertEq(fresh.lastTransitionAt(), 0, "No history fabricated");
    }

    // Scenarios: BLYC-REENABLE-P03.
    function test_givenExpiredGrace_whenReEnabled_reverts(
        address caller_,
        uint8 roleClass_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        grace_ = _boundUint32(grace_, 1, type(uint32).max);
        last_ = _boundUint48(last_, 1, type(uint48).max - grace_ - 1);
        _pauseAt(last_, grace_);
        uint48 deadline = last_ + grace_;
        now_ = _boundUint48(now_, deadline + 1, type(uint48).max);
        vm.warp(now_);
        target.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        claimer.reEnable();
        assertFalse(claimer.isEnabled(), "Expired grace cannot activate");
    }

    // Scenarios: BLYC-REENABLE-N01.
    function test_givenOverflowingDeadline_whenReEnabled_reverts(
        address caller_,
        uint8 roleClass_,
        uint48 last_,
        uint32 grace_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        grace_ = _boundUint32(grace_, 1, type(uint32).max);
        last_ = _boundUint48(last_, type(uint48).max - grace_ + 1, type(uint48).max);
        _pauseAt(last_, grace_);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(last_) + grace_
            )
        );
        vm.prank(caller_);
        claimer.reEnable();
        assertFalse(claimer.isEnabled(), "Overflow leaves task paused");
    }

    // Scenarios: BLYC-REENABLE-D01, BLYC-REENABLE-D02, BLYC-REENABLE-D03.
    function test_givenUnavailableCore_whenReEnabled_reverts(
        address caller_,
        uint8 roleClass_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _grantClaimerAdmin(caller_, roleClass_);
        _pauseAt(1000, 100);
        _setTargetLifecycle(active_, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(target)
            )
        );
        vm.prank(caller_);
        claimer.reEnable();
        assertFalse(claimer.isEnabled(), "Re-enable revalidates readiness");
    }

    // Scenarios: BLYC-REENABLE-P04.
    function test_givenSettlementRoleRevoked_whenReEnabled_reverts(
        address caller_,
        uint8 roleClass_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _pauseAt(1000, 100);
        vm.prank(admin);
        rolesAdmin.revokeRole(BL_YIELD_CLAIMER_ROLE, address(claimer));
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_YIELD_CLAIMER_ROLE)
        );
        vm.prank(caller_);
        claimer.reEnable();
    }

    // Scenarios: BLYC-REENABLE-D04.
    function test_givenCoreMigrated_whenReEnabled_reverts(
        address caller_,
        uint8 roleClass_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _pauseAt(1000, 100);
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
        vm.prank(caller_);
        claimer.reEnable();
    }

    // Scenarios: BLYC-REENABLE-L03.
    function test_givenInactiveTask_whenReEnabled_reverts(
        address caller_,
        uint8 roleClass_
    ) public {
        _grantClaimerAdmin(caller_, roleClass_);
        _pauseAt(1000, 100);
        _setClaimerLifecycle(false, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(claimer)
            )
        );
        vm.prank(caller_);
        claimer.reEnable();
    }

    // Scenarios: BLYC-REENABLE-P03.
    function test_whenExpiredTimeBoundarySeeds_reverts() public {
        uint256 snapshot = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass) {
            test_givenExpiredGrace_whenReEnabled_reverts(address(0xBEEF), roleClass, 1, 1, 3);
            vm.revertToState(snapshot);
            test_givenExpiredGrace_whenReEnabled_reverts(
                address(0xBEEF),
                roleClass,
                1,
                type(uint32).max,
                type(uint48).max
            );
            vm.revertToState(snapshot);
        }
    }

    // Scenarios: BLYC-REENABLE-N01.
    function test_whenOverflowBoundarySeeds_reverts() public {
        uint256 snapshot = vm.snapshotState();
        for (uint8 roleClass; roleClass < 3; ++roleClass) {
            test_givenOverflowingDeadline_whenReEnabled_reverts(
                address(0xBEEF),
                roleClass,
                type(uint48).max,
                1
            );
            vm.revertToState(snapshot);
            test_givenOverflowingDeadline_whenReEnabled_reverts(
                address(0xBEEF),
                roleClass,
                type(uint48).max - type(uint32).max + 1,
                type(uint32).max
            );
            vm.revertToState(snapshot);
        }
    }

    // Scenarios: BLYC-REENABLE-L01.
    function test_givenEnabledAtTimestampZero_whenReEnabled_reverts(address caller_) public {
        vm.prank(admin);
        claimer.disable("");
        vm.warp(0);
        vm.prank(admin);
        claimer.enable("");
        assertEq(
            claimer.lastTransitionAt(),
            0,
            "Reachable zero timestamp without storage mutation"
        );
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        claimer.reEnable();
    }
}
