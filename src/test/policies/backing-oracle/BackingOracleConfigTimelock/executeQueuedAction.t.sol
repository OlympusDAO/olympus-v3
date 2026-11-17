// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Contracts
import {BackingOracleConfigTimelockTest, IBackingOracle, IEnabler, ITimelockBatchQueue, IConfigTimelockBatchQueue} from "./fixtures/BackingOracleConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";

contract BackingOracleExecuteQueuedActionTest is BackingOracleConfigTimelockTest {
    function _rejectMissing(uint64 id_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        _timelock.executeQueuedAction(id_);
    }

    // Scenarios: BO-EXECUTEQUEUEDACTION-10.
    function test_whenAbsentBoundarySeeds_reverts() public {
        _rejectMissing(0);
        _rejectMissing(1);
        _rejectMissing(type(uint64).max);
    }

    // Scenarios: BO-EXECUTEQUEUEDACTION-01.
    function test_whenPermissionlessExecution(
        address caller_,
        uint48 elapsed_
    ) public givenEnabled {
        uint64 id = _queue(110e18);
        elapsed_ = uint48(bound(elapsed_, 1 days, 8 days));
        vm.warp(vm.getBlockTimestamp() + elapsed_);
        vm.expectEmit(address(_oracle));
        emit IBackingOracle.BackingSet(110e18);
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionExecuted(id, caller_);
        vm.prank(caller_);
        _timelock.executeQueuedAction(id);
        assertEq(_oracle.backing(), 110e18, "executed backing");
        ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(id);
        assertTrue(a.executed, "terminal executed");
        assertEq(a.actions.length, 0, "payload cleared");
        assertEq(_timelock.pendingActionId(_backingKey()), 0, "successful dispatch releases key");
        assertEq(
            _timelock.getQueuedConfigStateCount(id, 0),
            0,
            "successful dispatch clears commitments"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            )
        );
        _timelock.executeQueuedAction(id);
    }

    // Scenarios: BO-EXECUTEQUEUEDACTION-02.
    function test_whenExactNotice() public givenEnabled {
        uint64 id = _queue(90e18);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(address(0xB0B));
        _timelock.executeQueuedAction(id);
        assertEq(_oracle.backing(), 90e18, "inclusive executable boundary");
    }

    // Scenarios: BO-EXECUTEQUEUEDACTION-03.
    function test_whenExactExpiry() public givenEnabled {
        uint64 id = _queue(110e18);
        vm.warp(vm.getBlockTimestamp() + 8 days);
        vm.prank(address(0xB0B));
        _timelock.executeQueuedAction(id);
        assertEq(_oracle.backing(), 110e18, "inclusive expiry boundary");
    }

    // Scenarios: BO-EXECUTEQUEUEDACTION-04.
    function test_whenBeforeNotice_reverts() public givenEnabled {
        uint64 id = _queue(110e18);
        uint48 ready = uint48(vm.getBlockTimestamp() + 1 days);
        vm.warp(ready - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                id,
                ready
            )
        );
        _timelock.executeQueuedAction(id);
    }

    // Scenarios: BO-EXECUTEQUEUEDACTION-05.
    function test_whenAfterExpiry_reverts() public givenEnabled {
        uint64 id = _queue(110e18);
        uint48 expiry = uint48(vm.getBlockTimestamp() + 8 days);
        vm.warp(expiry + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                id,
                expiry
            )
        );
        _timelock.executeQueuedAction(id);
        assertFalse(_timelock.getQueuedAction(id).executed, "expired remains pending");
    }

    // Scenarios: BO-EXECUTEQUEUEDACTION-06.
    function test_givenBackingDrift_whenExecute_reverts() public givenEnabled {
        uint64 id = _queue(110e18);
        vm.prank(_ADMIN);
        _oracle.setBacking(90e18);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                id,
                uint256(0),
                _backingKey(),
                _stateHash(100e18),
                _stateHash(90e18)
            )
        );
        _timelock.executeQueuedAction(id);
        ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(id);
        assertFalse(a.executed, "failed dispatch rolls back executed flag");
        assertEq(a.actions[0].payload, abi.encode(110e18), "failed dispatch retains payload");
        assertEq(_oracle.backing(), 90e18, "failed dispatch preserves backing");
        vm.prank(_ADMIN);
        _oracle.setBacking(99e18);
        vm.prank(_ADMIN);
        _oracle.setBacking(100e18);
        _timelock.executeQueuedAction(id);
        assertEq(_oracle.backing(), 110e18, "retry uses original intent");
    }

    // Scenarios: BO-EXECUTEQUEUEDACTION-07.
    function test_givenDisabled_whenExecute_reverts() public givenEnabled {
        uint64 id = _queue(110e18);
        vm.prank(_ADMIN);
        _oracle.disable("");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _expectTargetUnavailable();
        _timelock.executeQueuedAction(id);
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(100e18));
        _timelock.executeQueuedAction(id);
        assertEq(_oracle.backing(), 110e18, "pending survives pause");
    }

    // Scenarios: BO-EXECUTEQUEUEDACTION-08.
    function test_givenInactive_whenExecute_reverts() public givenEnabled {
        uint64 id = _queue(110e18);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_oracle));
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _expectTargetUnavailable();
        _timelock.executeQueuedAction(id);
        _kernel.executeAction(Actions.ActivatePolicy, address(_oracle));
        _timelock.executeQueuedAction(id);
        assertEq(_oracle.backing(), 110e18, "pending survives reactivation");
    }

    // Scenarios: BO-EXECUTEQUEUEDACTION-09.
    function test_whenAbsent_reverts(uint64 id_) public {
        _rejectMissing(id_);
    }

    // Scenarios: BO-TIMELOCK-EXECUTEQUEUEDACTION-03.
    function test_givenOwnPaused_whenExecute_reverts() public givenEnabled {
        uint64 id = _queue(110e18);
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        _timelock.executeQueuedAction(id);
        vm.prank(_ADMIN);
        _timelock.enable("");
        _timelock.executeQueuedAction(id);
        assertEq(_timelock.pendingActionId(_backingKey()), 0, "successful retry releases key");
    }

    // Scenarios: BO-TIMELOCK-EXECUTEQUEUEDACTION-02.
    function test_givenOwnInactive_whenExecute_reverts() public givenEnabled {
        uint64 id = _queue(110e18);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _expectTimelockInactive();
        _timelock.executeQueuedAction(id);
        _kernel.executeAction(Actions.ActivatePolicy, address(_timelock));
        _timelock.executeQueuedAction(id);
        assertEq(_oracle.backing(), 110e18, "retry after queue reactivation");
    }

    // Scenarios: BO-TIMELOCK-EXECUTEQUEUEDACTION-01.
    function test_givenTargetFailure_whenExecute_reverts() public givenEnabled {
        uint64 id = _queue(110e18);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        bytes memory errorData = abi.encodeWithSelector(
            IBackingOracle.BackingOracle_ZeroBacking.selector
        );
        vm.mockCallRevert(
            address(_oracle),
            abi.encodeWithSelector(IBackingOracle.setBacking.selector, 110e18),
            errorData
        );
        vm.expectRevert(errorData);
        _timelock.executeQueuedAction(id);
        assertFalse(_timelock.getQueuedAction(id).executed, "downstream failure rolls back flag");
        assertEq(
            _timelock.pendingActionId(_backingKey()),
            id,
            "downstream failure retains reservation"
        );
        assertEq(_oracle.backing(), 100e18, "downstream failure preserves backing");
        vm.clearMockedCalls();
        _timelock.executeQueuedAction(id);
        assertEq(_timelock.pendingActionId(_backingKey()), 0, "retry releases reservation");
    }
}
