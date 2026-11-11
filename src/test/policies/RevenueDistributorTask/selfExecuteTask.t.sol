// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskSelfExecuteTaskTest is RevenueDistributorTaskTest {
    // Scenarios: SELF-A01.
    function test_whenExternalCallerExecutesTaskDirectly_reverts(
        address caller_,
        bool taskActive_,
        bool taskEnabled_,
        bool distributorActive_,
        bool distributorEnabled_
    ) public {
        vm.assume(caller_ != address(task));
        uint64 id = _seedTaskLifecycleQueue();
        _setTaskLifecycle(taskActive_, taskEnabled_);
        _setDistributorLifecycle(distributorActive_, distributorEnabled_);

        bytes32 beforeState = _taskStateDigest(id);
        vm.mockCallRevert(
            address(distributor),
            abi.encodeWithSignature("getActiveAssetCount()"),
            abi.encodeWithSignature("UnexpectedRead()")
        );
        vm.recordLogs();
        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_OnlySelf.selector);
        vm.prank(caller_);
        task.selfExecuteTask();

        assertEq(_taskStateDigest(id), beforeState, "All funded state and settings preserved");
        assertEq(vm.getRecordedLogs().length, 0, "Only-self rejection commits no logs");
    }

    function test_whenRoleBearingExternalCallerExecutesTaskDirectly_reverts(
        uint8 callerIndex_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        address[5] memory callers = [admin, alice, bob, emergency, address(distributor)];
        callerIndex_ = _boundUint8(callerIndex_, 0, 4);

        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_OnlySelf.selector);
        vm.prank(callers[callerIndex_]);
        task.selfExecuteTask();
    }

    // Scenarios: SELF-A01.
    function test_givenExternalCallerAndLifecycleSeeds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), false, false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, false, false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, false, false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, false, false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, false, false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            false,
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), false, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, false, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, false, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, false, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, false, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            false,
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), false, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, false, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, false, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, false, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, false, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            false,
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), false, false, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, false, false, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, false, false, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, false, false, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, false, false, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            false,
            false,
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), false, true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, false, true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, false, true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, false, true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, false, true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            false,
            true,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), false, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, false, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, false, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, false, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, false, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            false,
            true,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), false, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, false, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, false, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, false, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, false, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            false,
            true,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), false, true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, false, true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, false, true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, false, true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, false, true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            false,
            true,
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), true, false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, true, false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, true, false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, true, false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, true, false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            true,
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), true, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, true, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, true, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, true, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, true, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            true,
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), true, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, true, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, true, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, true, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, true, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            true,
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), true, false, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, true, false, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, true, false, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, true, false, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, true, false, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            true,
            false,
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), true, true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, true, true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, true, true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, true, true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, true, true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            true,
            true,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), true, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, true, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, true, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, true, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, true, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            true,
            true,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), true, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, true, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, true, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, true, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, true, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            true,
            true,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(address(0), true, true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(admin, true, true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(alice, true, true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(bob, true, true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(emergency, true, true, true, true);
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
        test_whenExternalCallerExecutesTaskDirectly_reverts(
            address(distributor),
            true,
            true,
            true,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore self-call authorization seed");
        vm.clearMockedCalls();
    }
}
