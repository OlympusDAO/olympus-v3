// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansYieldClaimer} from "src/policies/BurnerLoansYieldClaimer.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerReEnableTest is BurnerLoansYieldClaimerTest {
    uint48 internal constant _DISABLE_TIME = 1_000;

    // Scenarios: BLYC-REENABLE-P01, BLYC-REENABLE-P02.
    function test_givenDisabledWithinGrace_whenPermittedCallerReEnables(
        bool adminCalls_,
        bool active_,
        uint8 timePoint_
    ) public {
        address[] memory assets = new address[](2);
        assets[0] = address(0xA11CE);
        assets[1] = address(0xB0B);
        target.setAssets(assets);
        vm.prank(admin);
        claimer.setNextAssetIndex(1);
        vm.warp(_DISABLE_TIME);
        vm.prank(_emergency);
        claimer.disable("prior disable");
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(claimer));
        }
        address caller = _authorizedClaimerAdmin(adminCalls_);
        uint48 disabledAt = claimer.lastTransitionAt();
        uint48 deadline = disabledAt + claimer.gracePeriod();
        timePoint_ = _boundUint8(timePoint_, 0, 2);
        uint48 reEnableAt = timePoint_ == 0
            ? disabledAt
            : (timePoint_ == 1 ? deadline - 1 : deadline);
        vm.warp(reEnableAt);
        uint32 executionLimit = claimer.executionGasLimit();
        uint32 threshold = claimer.minimumGasToAttempt();
        uint32 reserve = claimer.gasReserve();
        uint256 cursor = claimer.nextAssetIndex();

        vm.expectEmit(false, false, false, false, address(claimer));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(claimer));
        emit IEnablerV2.Transition(caller, true, "", reEnableAt);
        vm.prank(caller);
        claimer.reEnable();

        assertTrue(claimer.isEnabled(), "permitted caller re-enables claimer");
        assertEq(claimer.lastTransitionAt(), reEnableAt, "re-enable records timestamp");
        assertEq(claimer.executionGasLimit(), executionLimit, "execution limit preserved");
        assertEq(claimer.minimumGasToAttempt(), threshold, "threshold preserved");
        assertEq(claimer.gasReserve(), reserve, "reserve preserved");
        assertEq(claimer.nextAssetIndex(), cursor, "cursor preserved");
    }

    // Scenarios: BLYC-REENABLE-I01.
    function test_givenEnabled_whenReEnableCalled_revertsBeforeOtherChecks(
        address caller_,
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
        claimer.reEnable();

        assertTrue(claimer.isEnabled(), "claimer remains enabled");
    }

    // Scenarios: BLYC-REENABLE-I02.
    function test_givenNeverEnabled_whenReEnableCalled_revertsBeforeOtherChecks(
        address caller_,
        bool taskActive_,
        bool targetActive_
    ) public {
        BurnerLoansYieldClaimer fresh = new BurnerLoansYieldClaimer(
            kernel,
            address(target),
            _EXECUTION_GAS_LIMIT
        );
        if (taskActive_) {
            vm.prank(admin);
            kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        }
        if (!targetActive_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(target));
        }

        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();

        assertFalse(fresh.isEnabled(), "fresh claimer remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "timestamp remains zero");
    }

    // Scenarios: BLYC-REENABLE-A01.
    function test_givenDisabled_whenUnauthorizedCallerReEnables_reverts(
        address caller_,
        bool taskActive_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        vm.prank(_emergency);
        claimer.disable("");
        if (!taskActive_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(claimer));
        }
        uint48 transitionAt = claimer.lastTransitionAt();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.reEnable();

        assertFalse(claimer.isEnabled(), "claimer remains disabled");
        assertEq(claimer.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    // Scenarios: BLYC-REENABLE-I03.
    function test_givenBurnerLoansPolicyInactive_whenPermittedCallerReEnables_reverts(
        bool adminCalls_,
        bool taskActive_
    ) public {
        vm.prank(_emergency);
        claimer.disable("");
        if (!taskActive_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(claimer));
        }
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(target));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidBurnerLoans.selector,
                address(target)
            )
        );
        vm.prank(_authorizedClaimerAdmin(adminCalls_));
        claimer.reEnable();

        assertFalse(claimer.isEnabled(), "claimer remains disabled");
    }

    // Scenarios: BLYC-REENABLE-I04.
    function test_givenGraceExpired_whenPermittedCallerReEnables_reverts(
        bool adminCalls_,
        bool taskActive_,
        uint48 timestamp_
    ) public {
        vm.warp(_DISABLE_TIME);
        vm.prank(_emergency);
        claimer.disable("");
        if (!taskActive_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(claimer));
        }
        uint48 transitionAt = claimer.lastTransitionAt();
        uint48 deadline = transitionAt + claimer.gracePeriod();
        timestamp_ = _boundUint48(timestamp_, deadline + 1, type(uint48).max);
        vm.warp(timestamp_);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(_authorizedClaimerAdmin(adminCalls_));
        claimer.reEnable();

        assertFalse(claimer.isEnabled(), "expired claimer remains disabled");
        assertEq(claimer.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    // Scenarios: BLYC-REENABLE-I05.
    function test_givenGraceExpiredAndTargetInactive_revertsBeforeTargetValidation(
        bool adminCalls_,
        bool taskActive_
    ) public {
        vm.warp(_DISABLE_TIME);
        vm.prank(_emergency);
        claimer.disable("");
        if (!taskActive_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(claimer));
        }
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(target));
        uint48 transitionAt = claimer.lastTransitionAt();
        uint48 deadline = transitionAt + claimer.gracePeriod();
        vm.warp(uint256(deadline) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(_authorizedClaimerAdmin(adminCalls_));
        claimer.reEnable();

        assertFalse(claimer.isEnabled(), "expired claimer remains disabled");
        assertEq(claimer.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }
}
