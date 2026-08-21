// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";
import {MockConfigTarget} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/MockConfigTarget.sol";

contract ConfigTimelockBatchQueueExecuteQueuedActionTest is ConfigTimelockBatchQueueTest {
    function test_executeQueuedAction_givenDisjointKeys_executesInArrayOrder() public {
        uint64 actionId = _queue.queueBatch(_batch(_KEY_A, _KEY_B));
        _warpReady(actionId);
        _queue.executeQueuedAction(actionId);

        assertEq(_target.executionOrder(0), 1, "first dispatch order");
        assertEq(_target.executionOrder(1), 2, "second dispatch order");
        assertEq(_target.configState(_KEY_A), 11, "first config applied");
        assertEq(_target.configState(_KEY_B), 22, "second config applied");
    }

    function test_executeQueuedAction_givenIndependentBatches_allowsReverseExecutionOrder() public {
        uint64 first = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        uint64 second = _queue.queueConfig(_keys(_KEY_B), _values(22), 2);
        _warpReady(second);

        _queue.executeQueuedAction(second);
        _queue.executeQueuedAction(first);

        assertEq(_target.executionOrder(0), 2, "second batch executes first");
        assertEq(_target.executionOrder(1), 1, "first batch executes second");
    }

    function test_executeQueuedAction_givenStateDrift_revertsAndKeepsGuard() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        bytes32 scopedKey = _scopedKey(_KEY_A);
        bytes32 expectedHash = keccak256(abi.encode(_KEY_A, uint256(10)));
        _target.setConfigState(_KEY_A, 99);
        bytes32 currentHash = keccak256(abi.encode(_KEY_A, uint256(99)));
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                uint256(0),
                scopedKey,
                expectedHash,
                currentHash
            )
        );
        _queue.executeQueuedAction(actionId);

        assertEq(_queue.pendingActionId(scopedKey), actionId, "drifted key remains held");
        assertEq(_queue.getQueuedConfigStateCount(actionId, 0), 1, "guard remains stored");
        assertEq(_target.configState(_KEY_A), 99, "out-of-band drift retained");
    }

    function test_executeQueuedAction_givenDestinationChanged_revertsAndKeepsGuard() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        MockConfigTarget newDestination = new MockConfigTarget();
        _queue.setConfigDestination(newDestination);
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigDestinationChanged
                    .selector,
                actionId,
                uint256(0),
                address(_target),
                address(newDestination)
            )
        );
        _queue.executeQueuedAction(actionId);

        assertEq(
            _queue.pendingActionId(_scopedKey(address(_target), _KEY_A)),
            actionId,
            "original destination key remains held"
        );
        assertEq(_target.configState(_KEY_A), 10, "original destination unchanged");
        assertFalse(_queue.getQueuedAction(actionId).executed, "action remains pending");
    }

    function test_executeQueuedAction_givenAnyMultiKeyDependencyDrifts_revertsBeforeDispatch()
        public
    {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A, _KEY_B), _values(11, 22), 1);
        bytes32 scopedKeyB = _scopedKey(_KEY_B);
        _target.setConfigState(_KEY_B, 99);
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                uint256(0),
                scopedKeyB,
                keccak256(abi.encode(_KEY_B, uint256(20))),
                keccak256(abi.encode(_KEY_B, uint256(99)))
            )
        );
        _queue.executeQueuedAction(actionId);

        assertEq(_target.executionOrderLength(), 0, "dispatch not entered");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), actionId, "first key remains held");
        assertEq(_queue.pendingActionId(scopedKeyB), actionId, "drifted key remains held");
    }

    function test_givenLaterSubActionStateDrift_executeQueuedAction_rollsBackEarlierDispatch()
        public
    {
        uint64 actionId = _queue.queueBatch(_batch(_KEY_A, _KEY_B));
        _target.setConfigState(_KEY_B, 99);
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                uint256(1),
                _scopedKey(_KEY_B),
                keccak256(abi.encode(_KEY_B, uint256(20))),
                keccak256(abi.encode(_KEY_B, uint256(99)))
            )
        );
        _queue.executeQueuedAction(actionId);

        assertEq(_target.configState(_KEY_A), 10, "earlier target write rolled back");
        assertEq(_target.configState(_KEY_B), 99, "out-of-band drift retained");
        assertEq(_target.executionOrderLength(), 0, "execution log rolled back");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), actionId, "earlier key remains held");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), actionId, "drifted key remains held");
        assertFalse(_queue.getQueuedAction(actionId).executed, "action remains pending");
    }

    function test_givenTransitiveDependencyAcrossKeys_executeQueuedAction_revertsAtomically()
        public
    {
        _queue.setStateHashDependency(_KEY_B, _KEY_A);
        uint64 actionId = _queue.queueBatch(_batch(_KEY_A, _KEY_B));
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                uint256(1),
                _scopedKey(_KEY_B),
                keccak256(abi.encode(_KEY_B, uint256(10))),
                keccak256(abi.encode(_KEY_B, uint256(11)))
            )
        );
        _queue.executeQueuedAction(actionId);

        assertEq(_target.configState(_KEY_A), 10, "dependency write rolled back");
        assertEq(_target.configState(_KEY_B), 20, "dependent state unchanged");
        assertEq(_target.executionOrderLength(), 0, "execution log rolled back");
        assertEq(
            _queue.pendingActionId(_scopedKey(_KEY_A)),
            actionId,
            "dependency key remains held"
        );
        assertEq(
            _queue.pendingActionId(_scopedKey(_KEY_B)),
            actionId,
            "dependent key remains held"
        );
        assertFalse(_queue.getQueuedAction(actionId).executed, "action remains pending");
    }

    function test_executeQueuedAction_givenLaterDispatchReverts_rollsBackTargetsAndGuards() public {
        uint64 actionId = _queue.queueBatch(_batch(_KEY_A, _KEY_B));
        _target.setRevertMarker(2);
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(MockConfigTarget.MockConfigTarget_ExecutionReverted.selector, 2)
        );
        _queue.executeQueuedAction(actionId);

        assertEq(_target.configState(_KEY_A), 10, "first target write rolled back");
        assertEq(_target.configState(_KEY_B), 20, "second target unchanged");
        assertEq(_target.executionOrderLength(), 0, "execution log rolled back");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), actionId, "first key remains held");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), actionId, "second key remains held");
    }

    function test_executeQueuedAction_releasesAllKeysOnlyAfterWholeBatchCompletes() public {
        uint64 actionId = _queue.queueBatch(_batch(_KEY_A, _KEY_B));
        _target.setReentry(address(_queue), _KEY_A);
        _target.setReentryMarker(2);
        _warpReady(actionId);

        _queue.executeQueuedAction(actionId);

        assertTrue(_target.reentryAttempted(), "reentry attempted");
        assertFalse(_target.reentrySucceeded(), "held key blocks reentry");
        assertEq(_queue.nextActionId(), 2, "reentrant queue did not consume action id");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "first key released at completion");
        assertEq(
            _queue.pendingActionId(_scopedKey(_KEY_B)),
            0,
            "second key released at completion"
        );
        assertEq(_target.configState(_KEY_A), 11, "first config applied");
        assertEq(_target.configState(_KEY_B), 22, "second config applied");
    }

    function test_executeQueuedAction_releasesEveryKeyAndClearsEveryGuard() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _queue.makeAction(_keys(_KEY_A, _KEY_B), _values(11, 22), 1);
        actions[1] = _queue.makeAction(_keys(_KEY_C), _values(33), 2);
        uint64 actionId = _queue.queueBatch(actions);
        _warpReady(actionId);

        _queue.executeQueuedAction(actionId);

        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "first key released");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), 0, "second key released");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_C)), 0, "third key released");
        assertEq(_queue.getQueuedConfigStateCount(actionId, 0), 0, "first guards cleared");
        assertEq(_queue.getQueuedConfigStateCount(actionId, 1), 0, "second guards cleared");
    }

    function test_givenReleasedKey_executeQueuedAction_allowsKeyToBeQueuedAgain() public {
        uint64 executedActionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        _warpReady(executedActionId);
        _queue.executeQueuedAction(executedActionId);

        uint64 replacementActionId = _queue.queueConfig(_keys(_KEY_A), _values(12), 2);

        assertEq(
            _queue.pendingActionId(_scopedKey(_KEY_A)),
            replacementActionId,
            "replacement owns released key"
        );
        assertEq(replacementActionId, executedActionId + 1, "replacement action id");
    }

    function test_executeQueuedAction_givenOwnershipMismatch_revertsWithoutDeletingForeignLock()
        public
    {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        uint64 corruptOwner = 99;
        bytes32 scopedKey = _scopedKey(_KEY_A);
        assertEq(_queue.pendingActionId(scopedKey), actionId, "expected owner before corruption");
        vm.store(address(_queue), _pendingActionIdSlot(scopedKey), bytes32(uint256(corruptOwner)));
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigKeyOwnershipInvalid
                    .selector,
                actionId,
                uint256(0),
                scopedKey,
                corruptOwner
            )
        );
        _queue.executeQueuedAction(actionId);

        assertEq(_queue.pendingActionId(scopedKey), corruptOwner, "foreign owner retained");
        assertFalse(_queue.getQueuedAction(actionId).executed, "action remains pending");
    }
}
