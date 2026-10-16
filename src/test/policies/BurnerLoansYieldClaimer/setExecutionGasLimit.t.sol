// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerSetExecutionGasLimitTest is BurnerLoansYieldClaimerTest {
    // Scenarios: BLYC-GAS-A01.
    function test_givenUnauthorizedCaller_reverts(
        address caller_,
        uint32 gasLimit_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        _setClaimerLifecycle(active_, enabled_);
        uint32 limitBefore = claimer.executionGasLimit();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.setExecutionGasLimit(gasLimit_);

        assertEq(claimer.executionGasLimit(), limitBefore, "execution limit unchanged");
    }

    // Scenarios: BLYC-GAS-I01.
    function test_givenZeroLimit_reverts(bool adminCalls_, bool active_, bool enabled_) public {
        _setClaimerLifecycle(active_, enabled_);
        uint32 limitBefore = claimer.executionGasLimit();

        vm.expectRevert(
            IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_InvalidExecutionGasLimit.selector
        );
        vm.prank(_authorizedClaimerAdmin(adminCalls_));
        claimer.setExecutionGasLimit(0);

        assertEq(claimer.executionGasLimit(), limitBefore, "execution limit unchanged");
    }

    // Scenarios: BLYC-GAS-P01, BLYC-GAS-P02, BLYC-GAS-P03.
    function test_whenPermittedCallerSetsDifferentValidLimit_updatesConfiguration(
        uint32 gasLimit_,
        bool adminCalls_,
        bool active_,
        bool enabled_
    ) public {
        gasLimit_ = _boundUint32(gasLimit_, 1, type(uint32).max);
        uint32 currentLimit = claimer.executionGasLimit();
        if (gasLimit_ == currentLimit) {
            gasLimit_ = currentLimit == type(uint32).max ? currentLimit - 1 : currentLimit + 1;
        }
        _setClaimerLifecycle(active_, enabled_);
        uint32 thresholdBefore = claimer.minimumGasToAttempt();
        uint32 reserveBefore = claimer.gasReserve();
        uint32 gracePeriodBefore = claimer.gracePeriod();
        uint256 cursorBefore = claimer.nextAssetIndex();

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.ExecutionGasLimitSet(gasLimit_);
        vm.prank(_authorizedClaimerAdmin(adminCalls_));
        claimer.setExecutionGasLimit(gasLimit_);

        assertEq(claimer.executionGasLimit(), gasLimit_, "execution limit equals input");
        assertEq(claimer.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
        assertEq(claimer.gracePeriod(), gracePeriodBefore, "grace period unchanged");
        assertEq(claimer.nextAssetIndex(), cursorBefore, "cursor unchanged");
    }

    // Scenarios: BLYC-GAS-P03.
    function test_whenExecutionGasLimitBoundaryUsed_storesExactLimit(
        bool maximum_,
        bool adminCalls_,
        bool active_,
        bool enabled_
    ) public {
        uint32 gasLimit = maximum_ ? type(uint32).max : 1;
        _setClaimerLifecycle(active_, enabled_);

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.ExecutionGasLimitSet(gasLimit);
        vm.prank(_authorizedClaimerAdmin(adminCalls_));
        claimer.setExecutionGasLimit(gasLimit);

        assertEq(claimer.executionGasLimit(), gasLimit, "boundary execution limit stored");
    }

    // Scenarios: BLYC-GAS-P04.
    function test_whenPermittedCallerSetsCurrentLimit_isNoOp(
        bool adminCalls_,
        bool active_,
        bool enabled_
    ) public {
        address caller = _authorizedClaimerAdmin(adminCalls_);
        _setClaimerLifecycle(active_, enabled_);
        uint32 currentLimit = claimer.executionGasLimit();
        uint32 thresholdBefore = claimer.minimumGasToAttempt();
        uint32 reserveBefore = claimer.gasReserve();
        uint32 gracePeriodBefore = claimer.gracePeriod();
        uint256 cursorBefore = claimer.nextAssetIndex();

        vm.recordLogs();
        vm.prank(caller);
        claimer.setExecutionGasLimit(currentLimit);

        assertEq(vm.getRecordedLogs().length, 0, "same limit emits no event");
        assertEq(claimer.executionGasLimit(), currentLimit, "execution limit unchanged");
        assertEq(claimer.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
        assertEq(claimer.gasReserve(), reserveBefore, "reserve unchanged");
        assertEq(claimer.gracePeriod(), gracePeriodBefore, "grace period unchanged");
        assertEq(claimer.nextAssetIndex(), cursorBefore, "cursor unchanged");
    }
}
