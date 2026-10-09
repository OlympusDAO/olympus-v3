// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskSetGasReserveTest is RevenueDistributorTaskTest {
    // Scenarios: GAS-A01.
    function test_whenUnauthorizedCallerSetsReserve_reverts(
        address caller_,
        uint32 gasLimit_,
        bool disabled_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        vm.assume(caller_ != admin);
        vm.assume(caller_ != bob);
        _setTaskDisabled(disabled_);
        uint32 reserveBefore = task.gasReserve();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        task.setGasReserve(gasLimit_);

        assertEq(task.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: GAS-L01.
    function test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
        bool adminCalls_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        gasLimit_ = _boundUint32(gasLimit_, 1, task.minimumGasToAttempt() - 1);
        uint32 reserveBefore = task.gasReserve();
        _deactivateTask();

        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_PolicyInactive.selector);
        vm.prank(caller);
        task.setGasReserve(gasLimit_);

        assertEq(task.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: GAS-I01.
    function test_whenPermittedCallerSetsZeroReserve_reverts(
        bool adminCalls_,
        bool disabled_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        _setTaskDisabled(disabled_);
        uint32 reserveBefore = task.gasReserve();

        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_InvalidGasReserve.selector);
        vm.prank(caller);
        task.setGasReserve(0);

        assertEq(task.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: GAS-I02.
    function test_whenReserveReachesThreshold_reverts(
        bool adminCalls_,
        bool disabled_,
        uint32 threshold_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        threshold_ = _boundUint32(threshold_, task.gasReserve() + 1, type(uint32).max);
        vm.prank(admin);
        task.setMinimumGasToAttempt(threshold_);
        _setTaskDisabled(disabled_);
        gasLimit_ = _boundUint32(gasLimit_, threshold_, type(uint32).max);
        uint32 reserveBefore = task.gasReserve();

        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_InvalidGasReserve.selector);
        vm.prank(caller);
        task.setGasReserve(gasLimit_);

        assertEq(task.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: GAS-P01, GAS-P02.
    function test_whenPermittedCallerSetsValidReserve_updatesValue(
        bool adminCalls_,
        bool disabled_,
        uint32 threshold_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        threshold_ = _boundUint32(threshold_, 3, type(uint32).max);
        vm.startPrank(admin);
        task.setGasReserve(1);
        task.setMinimumGasToAttempt(threshold_);
        vm.stopPrank();
        _setTaskDisabled(disabled_);
        gasLimit_ = _boundUint32(gasLimit_, 2, threshold_ - 1);
        uint32 thresholdBefore = task.minimumGasToAttempt();
        uint32 executionLimitBefore = task.executionGasLimit();

        _assertReserveUpdate(caller, gasLimit_);

        assertEq(task.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
        assertEq(task.executionGasLimit(), executionLimitBefore, "execution limit unchanged");
    }

    // Scenarios: GAS-P03.
    function test_whenPermittedCallerSetsCurrentReserve_isNoOp(
        bool adminCalls_,
        bool disabled_,
        bool minimumThreshold_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        if (minimumThreshold_) {
            vm.startPrank(admin);
            task.setGasReserve(1);
            task.setMinimumGasToAttempt(2);
            vm.stopPrank();
        }
        _setTaskDisabled(disabled_);
        uint32 currentReserve = task.gasReserve();
        uint32 thresholdBefore = task.minimumGasToAttempt();
        uint32 executionLimitBefore = task.executionGasLimit();

        vm.recordLogs();
        vm.prank(caller);
        task.setGasReserve(currentReserve);

        assertEq(vm.getRecordedLogs().length, 0, "same reserve emits no event");
        assertEq(task.gasReserve(), currentReserve, "reserve unchanged");
        assertEq(task.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
        assertEq(task.executionGasLimit(), executionLimitBefore, "execution limit unchanged");
    }

    // Scenarios: GAS-P01.
    function test_whenReserveBoundariesSet_updatesValue(bool adminCalls_) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        vm.prank(admin);
        task.setMinimumGasToAttempt(type(uint32).max);

        _assertReserveUpdate(caller, 1);
        _assertReserveUpdate(caller, type(uint32).max - 1);
    }

    function _assertReserveUpdate(address caller_, uint32 gasLimit_) internal {
        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.GasReserveSet(gasLimit_);
        vm.prank(caller_);
        task.setGasReserve(gasLimit_);
        assertEq(task.gasReserve(), gasLimit_, "reserve equals input");
    }
}
