// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerSetGasReserveTest is BurnerLoansYieldClaimerTest {
    uint32 internal constant _MINIMUM_GAS_RESERVE = 100_000;

    // Scenarios: RES-A01.
    function test_whenUnauthorizedCallerSetsReserve_reverts(
        address caller_,
        uint32 gasLimit_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        _setClaimerLifecycle(active_, enabled_);
        uint32 reserveBefore = claimer.gasReserve();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.setGasReserve(gasLimit_);

        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: RES-I01.
    function test_whenPermittedCallerSetsReserveBelowMinimum_reverts(
        bool adminCalls_,
        bool active_,
        bool enabled_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        _setClaimerLifecycle(active_, enabled_);
        gasLimit_ = _boundUint32(gasLimit_, 0, _MINIMUM_GAS_RESERVE - 1);
        uint32 reserveBefore = claimer.gasReserve();

        vm.expectRevert(
            IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidGasReserve.selector
        );
        vm.prank(caller);
        claimer.setGasReserve(gasLimit_);

        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: RES-I02.
    function test_whenReserveReachesThreshold_reverts(
        bool adminCalls_,
        bool active_,
        bool enabled_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        _setClaimerLifecycle(active_, enabled_);
        gasLimit_ = _boundUint32(gasLimit_, claimer.minimumGasToAttempt(), type(uint32).max);
        uint32 reserveBefore = claimer.gasReserve();

        vm.expectRevert(
            IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidGasReserve.selector
        );
        vm.prank(caller);
        claimer.setGasReserve(gasLimit_);

        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: RES-I01, RES-I02.
    function test_whenReserveBoundaryIsInvalid_reverts(bool adminCalls_) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        uint32 threshold = claimer.minimumGasToAttempt();
        uint32 reserveBefore = claimer.gasReserve();
        _assertInvalidReserveBoundary(caller, 0, reserveBefore);
        _assertInvalidReserveBoundary(caller, 1, reserveBefore);
        _assertInvalidReserveBoundary(caller, _MINIMUM_GAS_RESERVE - 1, reserveBefore);
        _assertInvalidReserveBoundary(caller, threshold, reserveBefore);
        _assertInvalidReserveBoundary(caller, threshold + 1, reserveBefore);
        _assertInvalidReserveBoundary(caller, type(uint32).max, reserveBefore);
    }

    function _assertInvalidReserveBoundary(
        address caller_,
        uint32 invalid_,
        uint32 reserveBefore_
    ) internal {
        vm.expectRevert(
            IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidGasReserve.selector
        );
        vm.prank(caller_);
        claimer.setGasReserve(invalid_);
        assertEq(claimer.gasReserve(), reserveBefore_, "invalid boundary preserves reserve");
    }

    // Scenarios: RES-P01.
    function test_whenPermittedCallerSetsValidReserve_updatesValue(
        bool adminCalls_,
        bool active_,
        bool enabled_,
        uint32 threshold_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        threshold_ = _boundUint32(threshold_, _MINIMUM_GAS_RESERVE + 2, type(uint32).max);
        vm.startPrank(admin);
        claimer.setMinimumGasToAttempt(threshold_);
        vm.stopPrank();
        _setClaimerLifecycle(active_, enabled_);
        gasLimit_ = _boundUint32(gasLimit_, _MINIMUM_GAS_RESERVE + 1, threshold_ - 1);
        uint32 executionBefore = claimer.executionGasLimit();

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.GasReserveSet(gasLimit_);
        vm.prank(caller);
        claimer.setGasReserve(gasLimit_);

        assertEq(claimer.gasReserve(), gasLimit_, "reserve equals input");
        assertEq(claimer.minimumGasToAttempt(), threshold_, "threshold unchanged");
        assertEq(claimer.executionGasLimit(), executionBefore, "execution limit unchanged");
    }

    // Scenarios: RES-P01.
    function test_whenReserveBoundariesSet_updatesValue(bool adminCalls_) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        vm.prank(admin);
        claimer.setMinimumGasToAttempt(type(uint32).max);

        vm.prank(caller);
        claimer.setGasReserve(_MINIMUM_GAS_RESERVE);
        assertEq(claimer.gasReserve(), _MINIMUM_GAS_RESERVE, "minimum reserve stored");

        vm.prank(caller);
        claimer.setGasReserve(type(uint32).max - 1);
        assertEq(claimer.gasReserve(), type(uint32).max - 1, "maximum reserve stored");
    }

    // Scenarios: RES-P02.
    function test_whenPermittedCallerSetsCurrentReserve_isNoOp(
        bool adminCalls_,
        bool active_,
        bool enabled_
    ) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        _setClaimerLifecycle(active_, enabled_);
        uint32 current = claimer.gasReserve();

        vm.recordLogs();
        vm.prank(caller);
        claimer.setGasReserve(current);

        assertEq(vm.getRecordedLogs().length, 0, "same reserve emits no event");
        assertEq(claimer.gasReserve(), current, "reserve unchanged");
    }
}
