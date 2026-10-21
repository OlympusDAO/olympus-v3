// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskSetExecutionGasLimitTest is RevenueDistributorTaskTest {
    // Scenarios: GAS-A01.
    function test_whenUnauthorizedCallerSetsExecutionGas_reverts(
        address caller_,
        uint32 gasLimit_,
        bool disabled_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        vm.assume(caller_ != admin);
        vm.assume(caller_ != bob);
        _setTaskDisabled(disabled_);
        uint32 limitBefore = task.executionGasLimit();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        task.setExecutionGasLimit(gasLimit_);

        assertEq(task.executionGasLimit(), limitBefore, "execution limit unchanged");
    }

    // Scenarios: GAS-L01.
    function test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
        bool adminCalls_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        gasLimit_ = _boundUint32(gasLimit_, 1, type(uint32).max);
        uint32 limitBefore = task.executionGasLimit();
        _deactivateTask();

        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_PolicyInactive.selector);
        vm.prank(caller);
        task.setExecutionGasLimit(gasLimit_);

        assertEq(task.executionGasLimit(), limitBefore, "execution limit unchanged");
    }

    // Scenarios: GAS-I01.
    function test_whenPermittedCallerSetsZeroExecutionGas_reverts(
        bool adminCalls_,
        bool disabled_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        _setTaskDisabled(disabled_);
        uint32 limitBefore = task.executionGasLimit();

        vm.expectRevert(
            IRevenueDistributorTask.RevenueDistributorTask_InvalidExecutionGasLimit.selector
        );
        vm.prank(caller);
        task.setExecutionGasLimit(0);

        assertEq(task.executionGasLimit(), limitBefore, "execution limit unchanged");
    }

    // Scenarios: GAS-P01, GAS-P02.
    function test_whenPermittedCallerSetsPositiveExecutionGas_updatesValue(
        bool adminCalls_,
        bool disabled_,
        uint32 gasLimit_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        _setTaskDisabled(disabled_);
        gasLimit_ = _boundUint32(gasLimit_, 1, type(uint32).max);
        uint32 currentLimit = task.executionGasLimit();
        if (gasLimit_ == currentLimit) {
            gasLimit_ = currentLimit == type(uint32).max ? currentLimit - 1 : currentLimit + 1;
        }
        uint32 thresholdBefore = task.minimumGasToAttempt();
        uint32 reserveBefore = task.gasReserve();

        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.ExecutionGasLimitSet(gasLimit_);
        vm.prank(caller);
        task.setExecutionGasLimit(gasLimit_);

        assertEq(task.executionGasLimit(), gasLimit_, "execution limit equals input");
        assertEq(task.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
        assertEq(task.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: GAS-P03.
    function test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp(
        bool adminCalls_,
        bool disabled_
    ) public {
        address caller = _authorizedTaskAdmin(adminCalls_);
        _setTaskDisabled(disabled_);
        uint32 currentLimit = task.executionGasLimit();
        uint32 thresholdBefore = task.minimumGasToAttempt();
        uint32 reserveBefore = task.gasReserve();

        vm.recordLogs();
        vm.prank(caller);
        task.setExecutionGasLimit(currentLimit);

        assertEq(vm.getRecordedLogs().length, 0, "same limit emits no event");
        assertEq(task.executionGasLimit(), currentLimit, "execution limit unchanged");
        assertEq(task.minimumGasToAttempt(), thresholdBefore, "threshold unchanged");
        assertEq(task.gasReserve(), reserveBefore, "reserve unchanged");
    }

    // Scenarios: GAS-P01.
    function test_whenExecutionGasBoundariesSet_updatesValue() public {
        _assertExecutionGasUpdate(1);
        _assertExecutionGasUpdate(type(uint32).max);
    }

    function _assertExecutionGasUpdate(uint32 gasLimit_) internal {
        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.ExecutionGasLimitSet(gasLimit_);
        vm.prank(admin);
        task.setExecutionGasLimit(gasLimit_);
        assertEq(task.executionGasLimit(), gasLimit_, "boundary limit stored");
    }
}
