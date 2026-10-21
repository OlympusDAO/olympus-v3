// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerSetMinimumGasToAttemptTest is BurnerLoansYieldClaimerTest {
    // Scenarios: MIN-A01.
    function test_whenUnauthorizedCallerSetsMinimumGas_reverts(
        address caller_,
        uint32 gasLimit_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        _setClaimerLifecycle(active_, enabled_);
        uint32 thresholdBefore = claimer.minimumGasToAttempt();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.setMinimumGasToAttempt(gasLimit_);

        assertEq(claimer.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
    }

    // Scenarios: MIN-I01.
    function test_whenMinimumGasDoesNotExceedReserve_reverts(
        bool adminCalls_,
        bool active_,
        bool enabled_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        _setClaimerLifecycle(active_, enabled_);
        gasLimit_ = _boundUint32(gasLimit_, 0, claimer.gasReserve());
        uint32 thresholdBefore = claimer.minimumGasToAttempt();

        vm.expectRevert(
            IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidMinimumGasToAttempt.selector
        );
        vm.prank(caller);
        claimer.setMinimumGasToAttempt(gasLimit_);

        assertEq(claimer.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
    }

    // Scenarios: MIN-I01.
    function test_whenMinimumGasBoundaryIsInvalid_reverts(bool adminCalls_) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        uint32 reserve = claimer.gasReserve();
        uint32 thresholdBefore = claimer.minimumGasToAttempt();
        _assertInvalidMinimumGasBoundary(caller, 0, thresholdBefore);
        _assertInvalidMinimumGasBoundary(caller, 1, thresholdBefore);
        _assertInvalidMinimumGasBoundary(caller, reserve - 1, thresholdBefore);
        _assertInvalidMinimumGasBoundary(caller, reserve, thresholdBefore);
    }

    function _assertInvalidMinimumGasBoundary(
        address caller_,
        uint32 invalid_,
        uint32 thresholdBefore_
    ) internal {
        vm.expectRevert(
            IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidMinimumGasToAttempt.selector
        );
        vm.prank(caller_);
        claimer.setMinimumGasToAttempt(invalid_);
        assertEq(
            claimer.minimumGasToAttempt(),
            thresholdBefore_,
            "invalid boundary preserves threshold"
        );
    }

    // Scenarios: MIN-P01.
    function test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
        bool adminCalls_,
        bool active_,
        bool enabled_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        _setClaimerLifecycle(active_, enabled_);
        gasLimit_ = _boundUint32(gasLimit_, claimer.gasReserve() + 1, type(uint32).max);
        uint32 current = claimer.minimumGasToAttempt();
        if (gasLimit_ == current) {
            gasLimit_ = current == type(uint32).max ? current - 1 : current + 1;
        }
        uint32 reserveBefore = claimer.gasReserve();
        uint32 executionBefore = claimer.executionGasLimit();

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.MinimumGasToAttemptSet(gasLimit_);
        vm.prank(caller);
        claimer.setMinimumGasToAttempt(gasLimit_);

        assertEq(claimer.minimumGasToAttempt(), gasLimit_, "threshold equals input");
        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
        assertEq(claimer.executionGasLimit(), executionBefore, "execution limit unchanged");
    }

    // Scenarios: MIN-P01.
    function test_whenMinimumGasBoundariesSet_updatesValue(bool adminCalls_) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        uint32 minimum = claimer.gasReserve() + 1;

        vm.prank(caller);
        claimer.setMinimumGasToAttempt(minimum);
        assertEq(claimer.minimumGasToAttempt(), minimum, "minimum threshold stored");

        vm.prank(caller);
        claimer.setMinimumGasToAttempt(type(uint32).max);
        assertEq(claimer.minimumGasToAttempt(), type(uint32).max, "maximum threshold stored");
    }

    // Scenarios: MIN-P02.
    function test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
        bool adminCalls_,
        bool active_,
        bool enabled_
    ) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        _setClaimerLifecycle(active_, enabled_);
        uint32 current = claimer.minimumGasToAttempt();

        vm.recordLogs();
        vm.prank(caller);
        claimer.setMinimumGasToAttempt(current);

        assertEq(vm.getRecordedLogs().length, 0, "same threshold emits no event");
        assertEq(claimer.minimumGasToAttempt(), current, "threshold unchanged");
    }
}
