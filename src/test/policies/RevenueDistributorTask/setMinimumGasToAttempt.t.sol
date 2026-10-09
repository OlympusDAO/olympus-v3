// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskSetMinimumGasToAttemptTest is RevenueDistributorTaskTest {
    // Scenarios: GAS-A01.
    function test_whenUnauthorizedCallerSetsMinimumGas_reverts(
        address caller_,
        uint32 gasLimit_,
        bool disabled_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        vm.assume(caller_ != admin);
        vm.assume(caller_ != bob);
        _setTaskDisabled(disabled_);
        uint32 thresholdBefore = task.minimumGasToAttempt();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        task.setMinimumGasToAttempt(gasLimit_);

        assertEq(task.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
    }

    // Scenarios: GAS-L01.
    function test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
        bool adminCalls_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        gasLimit_ = _boundUint32(gasLimit_, task.gasReserve() + 1, type(uint32).max);
        uint32 thresholdBefore = task.minimumGasToAttempt();
        _deactivateTask();

        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_PolicyInactive.selector);
        vm.prank(caller);
        task.setMinimumGasToAttempt(gasLimit_);

        assertEq(task.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
    }

    // Scenarios: GAS-I01.
    function test_whenMinimumGasDoesNotExceedReserve_reverts(
        bool adminCalls_,
        bool disabled_,
        uint32 reserve_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        reserve_ = _boundUint32(reserve_, 1, task.minimumGasToAttempt() - 1);
        vm.prank(admin);
        task.setGasReserve(reserve_);
        _setTaskDisabled(disabled_);
        gasLimit_ = _boundUint32(gasLimit_, 0, reserve_);
        uint32 thresholdBefore = task.minimumGasToAttempt();

        vm.expectRevert(
            IRevenueDistributorTask.RevenueDistributorTask_InvalidMinimumGasToAttempt.selector
        );
        vm.prank(caller);
        task.setMinimumGasToAttempt(gasLimit_);

        assertEq(task.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
    }

    // Scenarios: GAS-P01, GAS-P02.
    function test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
        bool adminCalls_,
        bool disabled_,
        bool minimumReserve_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        if (minimumReserve_) {
            vm.prank(admin);
            task.setGasReserve(1);
        }
        _setTaskDisabled(disabled_);
        gasLimit_ = _boundUint32(gasLimit_, task.gasReserve() + 1, type(uint32).max);
        uint32 currentThreshold = task.minimumGasToAttempt();
        if (gasLimit_ == currentThreshold) {
            gasLimit_ = currentThreshold == type(uint32).max
                ? currentThreshold - 1
                : currentThreshold + 1;
        }
        uint32 reserveBefore = task.gasReserve();
        uint32 executionLimitBefore = task.executionGasLimit();

        _assertMinimumGasUpdate(caller, gasLimit_);

        assertEq(task.gasReserve(), reserveBefore, "reserve unchanged");
        assertEq(task.executionGasLimit(), executionLimitBefore, "execution limit unchanged");
    }

    // Scenarios: GAS-P03.
    function test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
        bool adminCalls_,
        bool disabled_,
        bool minimumReserve_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        if (minimumReserve_) {
            vm.prank(admin);
            task.setGasReserve(1);
        }
        _setTaskDisabled(disabled_);
        uint32 currentThreshold = task.minimumGasToAttempt();
        uint32 reserveBefore = task.gasReserve();
        uint32 executionLimitBefore = task.executionGasLimit();

        vm.recordLogs();
        vm.prank(caller);
        task.setMinimumGasToAttempt(currentThreshold);

        assertEq(vm.getRecordedLogs().length, 0, "same threshold emits no event");
        assertEq(task.minimumGasToAttempt(), currentThreshold, "threshold unchanged");
        assertEq(task.gasReserve(), reserveBefore, "reserve unchanged");
        assertEq(task.executionGasLimit(), executionLimitBefore, "execution limit unchanged");
    }

    // Scenarios: GAS-P01.
    function test_whenMinimumGasBoundariesSet_updatesValue(bool adminCalls_) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        uint32 firstValid = task.gasReserve() + 1;

        _assertMinimumGasUpdate(caller, firstValid);
        _assertMinimumGasUpdate(caller, type(uint32).max);
    }

    function _assertMinimumGasUpdate(address caller_, uint32 gasLimit_) internal {
        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.MinimumGasToAttemptSet(gasLimit_);
        vm.prank(caller_);
        task.setMinimumGasToAttempt(gasLimit_);
        assertEq(task.minimumGasToAttempt(), gasLimit_, "threshold equals input");
    }
}
