// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskMinimumGasToAttemptCoverageTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-MINIMUM-GAS-A01, RDTASK-MINIMUM-GAS-A02.
    function test_whenUnauthorizedCallerSetsMinimumGas_reverts(
        address caller_,
        uint32 gasLimit_,
        bool disabled_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE));
        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeexecutionGasLimit = task.executionGasLimit();
        uint256 beforegasReserve = task.gasReserve();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.minimumGasToAttempt();
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        task.setMinimumGasToAttempt(gasLimit_);
        assertEq(task.minimumGasToAttempt(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(task.gasReserve(), beforegasReserve, "Other task setting unchanged");
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-MINIMUM-GAS-L01.
    function test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        uint32 gasLimit_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        _deactivateTask();
        bytes32 context = _taskContextDigest(id);
        uint256 beforeexecutionGasLimit = task.executionGasLimit();
        uint256 beforegasReserve = task.gasReserve();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.minimumGasToAttempt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_PolicyNotActive.selector,
                address(task)
            )
        );
        vm.prank(caller_);
        task.setMinimumGasToAttempt(gasLimit_);
        assertEq(task.minimumGasToAttempt(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(task.gasReserve(), beforegasReserve, "Other task setting unchanged");
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-MINIMUM-GAS-I01, RDTASK-MINIMUM-GAS-I02.
    function test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_,
        uint32 reserve_,
        uint32 gasLimit_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        reserve_ = _boundUint32(reserve_, 1, type(uint32).max - 1);
        vm.startPrank(admin);
        task.setMinimumGasToAttempt(type(uint32).max);
        task.setGasReserve(reserve_);
        vm.stopPrank();
        gasLimit_ = _boundUint32(gasLimit_, 0, reserve_);
        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeexecutionGasLimit = task.executionGasLimit();
        uint256 beforegasReserve = task.gasReserve();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.minimumGasToAttempt();
        vm.recordLogs();
        vm.expectRevert(
            IRevenueDistributorTask.RevenueDistributorTask_InvalidMinimumGasToAttempt.selector
        );
        vm.prank(caller_);
        task.setMinimumGasToAttempt(gasLimit_);
        assertEq(task.minimumGasToAttempt(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(task.gasReserve(), beforegasReserve, "Other task setting unchanged");
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-MINIMUM-GAS-P01, RDTASK-MINIMUM-GAS-P02, RDTASK-MINIMUM-GAS-P04.
    function test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_,
        bool minimumReserve_,
        uint32 gasLimit_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        vm.prank(admin);
        task.setGasReserve(minimumReserve_ ? 1 : 100_000);
        gasLimit_ = _boundUint32(gasLimit_, task.gasReserve() + 1, type(uint32).max);
        vm.assume(gasLimit_ != task.minimumGasToAttempt());
        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeexecutionGasLimit = task.executionGasLimit();
        uint256 beforegasReserve = task.gasReserve();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.minimumGasToAttempt();
        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.MinimumGasToAttemptSet(gasLimit_);
        vm.recordLogs();
        vm.prank(caller_);
        task.setMinimumGasToAttempt(gasLimit_);
        assertEq(task.minimumGasToAttempt(), gasLimit_, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 1, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(task.gasReserve(), beforegasReserve, "Other task setting unchanged");
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-MINIMUM-GAS-P03, RDTASK-MINIMUM-GAS-P05.
    function test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_,
        bool minimumReserve_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        vm.prank(admin);
        task.setGasReserve(minimumReserve_ ? 1 : 100_000);
        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeexecutionGasLimit = task.executionGasLimit();
        uint256 beforegasReserve = task.gasReserve();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.minimumGasToAttempt();
        vm.recordLogs();
        vm.prank(caller_);
        task.setMinimumGasToAttempt(previous);
        assertEq(task.minimumGasToAttempt(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(task.gasReserve(), beforegasReserve, "Other task setting unchanged");
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-MINIMUM-GAS-A01, RDTASK-MINIMUM-GAS-A02, RDTASK-MINIMUM-GAS-I01, RDTASK-MINIMUM-GAS-I02, RDTASK-MINIMUM-GAS-L01, RDTASK-MINIMUM-GAS-P01, RDTASK-MINIMUM-GAS-P02, RDTASK-MINIMUM-GAS-P03, RDTASK-MINIMUM-GAS-P04, RDTASK-MINIMUM-GAS-P05.
    function test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenUnauthorizedCallerSetsMinimumGas_reverts(address(0), 0, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsMinimumGas_reverts(address(0), 1, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsMinimumGas_reverts(address(0), 4294967295, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            false,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            false,
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            false,
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            false,
            false,
            false,
            true,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            false,
            false,
            false,
            true,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            false,
            false,
            false,
            false,
            100001
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            false,
            false,
            false,
            false,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            false,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            false,
            1,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            false,
            4294967294,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            false,
            4294967294,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            false,
            4294967294,
            4294967293
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            false,
            4294967294,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            false,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            true,
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            true,
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            false,
            false,
            true,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            false,
            false,
            true,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            false,
            false,
            false,
            100001
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            false,
            false,
            false,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            false,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            false,
            1,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            false,
            4294967294,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            false,
            4294967294,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            false,
            4294967294,
            4294967293
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            false,
            4294967294,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            false,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            true,
            true,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            true,
            true,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            true,
            false,
            true,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            true,
            false,
            true,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            true,
            false,
            false,
            100001
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            true,
            false,
            false,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            false,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            false,
            1,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            false,
            4294967294,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            false,
            4294967294,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            false,
            4294967294,
            4294967293
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            false,
            4294967294,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsMinimumGas_reverts(address(0), 0, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsMinimumGas_reverts(address(0), 1, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsMinimumGas_reverts(address(0), 4294967295, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            true,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            false,
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            false,
            false,
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            false,
            false,
            true,
            true,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            false,
            false,
            true,
            true,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            false,
            false,
            true,
            false,
            100001
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            false,
            false,
            true,
            false,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            true,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            true,
            1,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            true,
            4294967294,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            true,
            4294967294,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            true,
            4294967294,
            4294967293
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            true,
            4294967294,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            true,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            true,
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            true,
            false,
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            false,
            true,
            true,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            false,
            true,
            true,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            false,
            true,
            false,
            100001
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            false,
            true,
            false,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            true,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            true,
            1,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            true,
            4294967294,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            true,
            4294967294,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            true,
            4294967294,
            4294967293
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            true,
            4294967294,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            true,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            true,
            true,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp(
            address(0x1234),
            true,
            true,
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            true,
            true,
            true,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            true,
            true,
            true,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            true,
            true,
            false,
            100001
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidMinimumGas_updatesValue(
            address(0x1234),
            true,
            true,
            true,
            false,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            true,
            1,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            true,
            1,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            true,
            4294967294,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            true,
            4294967294,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            true,
            4294967294,
            4294967293
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            true,
            4294967294,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");

        test_whenUnauthorizedCallerSetsMinimumGas_reverts(address(0), 100001, false);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_whenUnauthorizedCallerSetsMinimumGas_reverts(address(0), 100002, false);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_whenUnauthorizedCallerSetsMinimumGas_reverts(address(0), 100001, true);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_whenUnauthorizedCallerSetsMinimumGas_reverts(address(0), 100002, true);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            100002
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            false,
            false,
            type(uint32).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            100002
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            true,
            false,
            type(uint32).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            100002
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts(
            address(0x1234),
            true,
            true,
            type(uint32).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
    }

    // Scenarios: RDTASK-MINIMUM-GAS-L02.
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
        task.setMinimumGasToAttempt(value_);
    }
}
