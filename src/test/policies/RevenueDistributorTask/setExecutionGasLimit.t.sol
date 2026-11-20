// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskExecutionGasLimitCoverageTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-EXECUTION-GAS-A01, RDTASK-EXECUTION-GAS-A02.
    function test_whenUnauthorizedCallerSetsExecutionGas_reverts(
        address caller_,
        uint32 gasLimit_,
        bool disabled_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE));
        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforegasReserve = task.gasReserve();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.executionGasLimit();
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        task.setExecutionGasLimit(gasLimit_);
        assertEq(task.executionGasLimit(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.gasReserve(), beforegasReserve, "Other task setting unchanged");
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-EXECUTION-GAS-L01.
    function test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        uint32 gasLimit_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        _deactivateTask();
        bytes32 context = _taskContextDigest(id);
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforegasReserve = task.gasReserve();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.executionGasLimit();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_PolicyNotActive.selector,
                address(task)
            )
        );
        vm.prank(caller_);
        task.setExecutionGasLimit(gasLimit_);
        assertEq(task.executionGasLimit(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.gasReserve(), beforegasReserve, "Other task setting unchanged");
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-EXECUTION-GAS-I01, RDTASK-EXECUTION-GAS-I02.
    function test_whenPermittedCallerSetsInvalidExecutionGas_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);

        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforegasReserve = task.gasReserve();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.executionGasLimit();
        vm.recordLogs();
        vm.expectRevert(
            IRevenueDistributorTask.RevenueDistributorTask_InvalidExecutionGasLimit.selector
        );
        vm.prank(caller_);
        task.setExecutionGasLimit(0);
        assertEq(task.executionGasLimit(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.gasReserve(), beforegasReserve, "Other task setting unchanged");
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-EXECUTION-GAS-P01, RDTASK-EXECUTION-GAS-P02, RDTASK-EXECUTION-GAS-P04.
    function test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_,
        uint32 gasLimit_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        gasLimit_ = _boundUint32(gasLimit_, 1, type(uint32).max);
        vm.assume(gasLimit_ != task.executionGasLimit());
        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforegasReserve = task.gasReserve();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.executionGasLimit();
        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.ExecutionGasLimitSet(gasLimit_);
        vm.recordLogs();
        vm.prank(caller_);
        task.setExecutionGasLimit(gasLimit_);
        assertEq(task.executionGasLimit(), gasLimit_, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 1, "Exact setter log count");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.gasReserve(), beforegasReserve, "Other task setting unchanged");
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-EXECUTION-GAS-P03, RDTASK-EXECUTION-GAS-P05.
    function test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);

        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforegasReserve = task.gasReserve();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.executionGasLimit();
        vm.recordLogs();
        vm.prank(caller_);
        task.setExecutionGasLimit(previous);
        assertEq(task.executionGasLimit(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.gasReserve(), beforegasReserve, "Other task setting unchanged");
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-EXECUTION-GAS-A01, RDTASK-EXECUTION-GAS-A02, RDTASK-EXECUTION-GAS-I01, RDTASK-EXECUTION-GAS-I02, RDTASK-EXECUTION-GAS-L01, RDTASK-EXECUTION-GAS-P01, RDTASK-EXECUTION-GAS-P02, RDTASK-EXECUTION-GAS-P03, RDTASK-EXECUTION-GAS-P04, RDTASK-EXECUTION-GAS-P05.
    function test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenUnauthorizedCallerSetsExecutionGas_reverts(address(0), 0, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsExecutionGas_reverts(address(0), 1, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsExecutionGas_reverts(address(0), 4294967295, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidExecutionGas_reverts(
            address(0x1234),
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            false,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp(
            address(0x1234),
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            false,
            false,
            false,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            false,
            false,
            false,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidExecutionGas_reverts(
            address(0x1234),
            true,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            true,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp(address(0x1234), true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            true,
            false,
            false,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            true,
            false,
            false,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidExecutionGas_reverts(address(0x1234), true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            true,
            true,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp(address(0x1234), true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            true,
            true,
            false,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            true,
            true,
            false,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsExecutionGas_reverts(address(0), 0, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsExecutionGas_reverts(address(0), 1, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsExecutionGas_reverts(address(0), 4294967295, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidExecutionGas_reverts(
            address(0x1234),
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            false,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp(address(0x1234), false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            false,
            false,
            true,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            false,
            false,
            true,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidExecutionGas_reverts(address(0x1234), true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            true,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp(address(0x1234), true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            true,
            false,
            true,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            true,
            false,
            true,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidExecutionGas_reverts(address(0x1234), true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            true,
            true,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp(address(0x1234), true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            true,
            true,
            true,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidExecutionGas_updatesValue(
            address(0x1234),
            true,
            true,
            true,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");

        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            false,
            false,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            false,
            false,
            type(uint32).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            true,
            false,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            true,
            false,
            type(uint32).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            true,
            true,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts(
            address(0x1234),
            true,
            true,
            type(uint32).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
    }

    // Scenarios: RDTASK-EXECUTION-GAS-L02.
    function test_givenInactiveAndDisabled_whenAnyCallerSetsValue_revertsActivityFirst(
        address caller_,
        uint32 value_
    ) public {
        _setTaskDisabled(true);
        _deactivateTask();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_PolicyNotActive.selector,
                address(task)
            )
        );
        vm.prank(caller_);
        task.setExecutionGasLimit(value_);
    }
}
