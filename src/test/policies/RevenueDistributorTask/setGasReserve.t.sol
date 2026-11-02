// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskGasReserveCoverageTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-GAS-RESERVE-A01, RDTASK-GAS-RESERVE-A02.
    function test_whenUnauthorizedCallerSetsReserve_reverts(
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
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.gasReserve();
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        task.setGasReserve(gasLimit_);
        assertEq(task.gasReserve(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-GAS-RESERVE-L01.
    function test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
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
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.gasReserve();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_PolicyNotActive.selector,
                address(task)
            )
        );
        vm.prank(caller_);
        task.setGasReserve(gasLimit_);
        assertEq(task.gasReserve(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: GAS-I03, RDTASK-GAS-RESERVE-I01.
    function test_whenPermittedCallerSetsInvalidReserve_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);

        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeexecutionGasLimit = task.executionGasLimit();
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.gasReserve();
        vm.recordLogs();
        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_InvalidGasReserve.selector);
        vm.prank(caller_);
        task.setGasReserve(0);
        assertEq(task.gasReserve(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: GAS-I04, RDTASK-GAS-RESERVE-I02.
    function test_whenReserveReachesThreshold_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_,
        uint32 threshold_,
        uint32 gasLimit_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        threshold_ = _boundUint32(threshold_, 2, type(uint32).max);
        vm.startPrank(admin);
        task.setGasReserve(1);
        task.setMinimumGasToAttempt(threshold_);
        vm.stopPrank();
        gasLimit_ = _boundUint32(gasLimit_, threshold_, type(uint32).max);
        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeexecutionGasLimit = task.executionGasLimit();
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.gasReserve();
        vm.recordLogs();
        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_InvalidGasReserve.selector);
        vm.prank(caller_);
        task.setGasReserve(gasLimit_);
        assertEq(task.gasReserve(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-GAS-RESERVE-P01, RDTASK-GAS-RESERVE-P02, RDTASK-GAS-RESERVE-P04.
    function test_whenPermittedCallerSetsValidReserve_updatesValue(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_,
        uint32 threshold_,
        uint32 gasLimit_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        threshold_ = _boundUint32(threshold_, 3, type(uint32).max);
        vm.startPrank(admin);
        task.setGasReserve(1);
        task.setMinimumGasToAttempt(threshold_);
        vm.stopPrank();
        gasLimit_ = _boundUint32(gasLimit_, 2, threshold_ - 1);
        vm.assume(gasLimit_ != task.gasReserve());
        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeexecutionGasLimit = task.executionGasLimit();
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.gasReserve();
        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.GasReserveSet(gasLimit_);
        vm.recordLogs();
        vm.prank(caller_);
        task.setGasReserve(gasLimit_);
        assertEq(task.gasReserve(), gasLimit_, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 1, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-GAS-RESERVE-P03, RDTASK-GAS-RESERVE-P05.
    function test_whenPermittedCallerSetsCurrentReserve_isNoOp(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_,
        bool minimumThreshold_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        if (minimumThreshold_) {
            vm.startPrank(admin);
            task.setGasReserve(1);
            task.setMinimumGasToAttempt(2);
            vm.stopPrank();
        } else {
            vm.prank(admin);
            task.setMinimumGasToAttempt(250_000);
        }
        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeexecutionGasLimit = task.executionGasLimit();
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.gasReserve();
        vm.recordLogs();
        vm.prank(caller_);
        task.setGasReserve(previous);
        assertEq(task.gasReserve(), previous, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 0, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: RDTASK-GAS-RESERVE-P01, RDTASK-GAS-RESERVE-P02, RDTASK-GAS-RESERVE-P04.
    function test_whenMinimumReserveSet_updatesValue(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool disabled_
    ) public {
        uint64 id = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        uint32 gasLimit_ = 1;
        _setTaskDisabled(disabled_);
        bytes32 context = _taskContextDigest(id);
        uint256 beforeexecutionGasLimit = task.executionGasLimit();
        uint256 beforeminimumGasToAttempt = task.minimumGasToAttempt();
        uint256 beforenextAssetIndex = task.nextAssetIndex();
        uint32 previous = task.gasReserve();
        vm.expectEmit(false, false, false, true, address(task));
        emit IRevenueDistributorTask.GasReserveSet(gasLimit_);
        vm.recordLogs();
        vm.prank(caller_);
        task.setGasReserve(gasLimit_);
        assertEq(task.gasReserve(), gasLimit_, "Exact setting after call");
        assertEq(vm.getRecordedLogs().length, 1, "Exact setter log count");
        assertEq(task.executionGasLimit(), beforeexecutionGasLimit, "Other task setting unchanged");
        assertEq(
            task.minimumGasToAttempt(),
            beforeminimumGasToAttempt,
            "Other task setting unchanged"
        );
        assertEq(task.nextAssetIndex(), beforenextAssetIndex, "Other task setting unchanged");
        assertEq(_taskContextDigest(id), context, "Accounting, queue and lifecycle unchanged");
    }

    // Scenarios: GAS-I03, GAS-I04, RDTASK-GAS-RESERVE-A01, RDTASK-GAS-RESERVE-A02, RDTASK-GAS-RESERVE-I01, RDTASK-GAS-RESERVE-I02, RDTASK-GAS-RESERVE-L01, RDTASK-GAS-RESERVE-P01, RDTASK-GAS-RESERVE-P02, RDTASK-GAS-RESERVE-P03, RDTASK-GAS-RESERVE-P04, RDTASK-GAS-RESERVE-P05.
    function test_givenRoleAndNumericBoundaries_whenGasReserveSet() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 0, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 1, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 4294967295, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidReserve_reverts(address(0x1234), false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            false,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(
            address(0x1234),
            false,
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(
            address(0x1234),
            false,
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            false,
            false,
            false,
            3,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            false,
            false,
            false,
            4294967295,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenMinimumReserveSet_updatesValue(address(0x1234), false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), false, false, false, 2, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), false, false, false, 2, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(
            address(0x1234),
            false,
            false,
            false,
            2,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(
            address(0x1234),
            false,
            false,
            false,
            4294967295,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidReserve_reverts(address(0x1234), true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            true,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(
            address(0x1234),
            true,
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(
            address(0x1234),
            true,
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            true,
            false,
            false,
            3,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            true,
            false,
            false,
            4294967295,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenMinimumReserveSet_updatesValue(address(0x1234), true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), true, false, false, 2, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), true, false, false, 2, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(
            address(0x1234),
            true,
            false,
            false,
            2,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(
            address(0x1234),
            true,
            false,
            false,
            4294967295,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidReserve_reverts(address(0x1234), true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            true,
            true,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(
            address(0x1234),
            true,
            true,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(address(0x1234), true, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            true,
            true,
            false,
            3,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            true,
            true,
            false,
            4294967295,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenMinimumReserveSet_updatesValue(address(0x1234), true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), true, true, false, 2, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), true, true, false, 2, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), true, true, false, 2, 4294967295);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(
            address(0x1234),
            true,
            true,
            false,
            4294967295,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 0, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 1, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 4294967295, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidReserve_reverts(address(0x1234), false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            false,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(
            address(0x1234),
            false,
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(
            address(0x1234),
            false,
            false,
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            false,
            false,
            true,
            3,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            false,
            false,
            true,
            4294967295,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenMinimumReserveSet_updatesValue(address(0x1234), false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), false, false, true, 2, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), false, false, true, 2, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(
            address(0x1234),
            false,
            false,
            true,
            2,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(
            address(0x1234),
            false,
            false,
            true,
            4294967295,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidReserve_reverts(address(0x1234), true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            true,
            false,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(
            address(0x1234),
            true,
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(address(0x1234), true, false, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            true,
            false,
            true,
            3,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            true,
            false,
            true,
            4294967295,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenMinimumReserveSet_updatesValue(address(0x1234), true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), true, false, true, 2, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), true, false, true, 2, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), true, false, true, 2, 4294967295);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(
            address(0x1234),
            true,
            false,
            true,
            4294967295,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsInvalidReserve_reverts(address(0x1234), true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            true,
            true,
            0
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(address(0x1234), true, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsCurrentReserve_isNoOp(address(0x1234), true, true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            true,
            true,
            true,
            3,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenPermittedCallerSetsValidReserve_updatesValue(
            address(0x1234),
            true,
            true,
            true,
            4294967295,
            4294967294
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenMinimumReserveSet_updatesValue(address(0x1234), true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), true, true, true, 2, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), true, true, true, 2, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(address(0x1234), true, true, true, 2, 4294967295);
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");
        test_whenReserveReachesThreshold_reverts(
            address(0x1234),
            true,
            true,
            true,
            4294967295,
            4294967295
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent setter seed");

        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 250000, false);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 250001, false);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 250002, false);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 250000, true);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 250001, true);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_whenUnauthorizedCallerSetsReserve_reverts(address(0), 250002, true);
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            false,
            false,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            false,
            false,
            type(uint32).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            true,
            false,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            true,
            false,
            type(uint32).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            true,
            true,
            1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
        test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts(
            address(0x1234),
            true,
            true,
            type(uint32).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore semantic gas boundary");
    }

    // Scenarios: RDTASK-GAS-RESERVE-L02.
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
        task.setGasReserve(value_);
    }
}
