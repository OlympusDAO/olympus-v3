// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";
import {MockConfigTarget} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/MockConfigTarget.sol";

contract ConfigTimelockBatchQueueExecuteQueuedActionTest is ConfigTimelockBatchQueueTest {
    function test_executeQueuedAction_givenDisjointKeys_executesInArrayOrder() public {
        uint64 actionId = queue.queueBatch(_batch(KEY_A, KEY_B));
        _warpReady(actionId);
        queue.executeQueuedAction(actionId);

        assertEq(target.executionOrder(0), 1, "first dispatch order");
        assertEq(target.executionOrder(1), 2, "second dispatch order");
        assertEq(target.configState(KEY_A), 11, "first config applied");
        assertEq(target.configState(KEY_B), 22, "second config applied");
    }

    function test_executeQueuedAction_givenIndependentBatches_allowsReverseExecutionOrder() public {
        uint64 first = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        uint64 second = queue.queueConfig(_keys(KEY_B), _values(22), 2);
        _warpReady(second);

        queue.executeQueuedAction(second);
        queue.executeQueuedAction(first);

        assertEq(target.executionOrder(0), 2, "second batch executes first");
        assertEq(target.executionOrder(1), 1, "first batch executes second");
    }

    function test_executeQueuedAction_givenStateDrift_revertsAndKeepsGuard() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        bytes32 scopedKey = _scopedKey(KEY_A);
        bytes32 expectedHash = keccak256(abi.encode(KEY_A, uint256(10)));
        target.setConfigState(KEY_A, 99);
        bytes32 currentHash = keccak256(abi.encode(KEY_A, uint256(99)));
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
        queue.executeQueuedAction(actionId);

        assertEq(queue.pendingActionId(scopedKey), actionId, "drifted key remains held");
        assertEq(queue.getQueuedConfigStateCount(actionId, 0), 1, "guard remains stored");
        assertEq(target.configState(KEY_A), 99, "out-of-band drift retained");
    }

    function test_executeQueuedAction_givenDestinationChanged_revertsAndKeepsGuard() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        MockConfigTarget newDestination = new MockConfigTarget();
        queue.setConfigDestination(newDestination);
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigDestinationChanged
                    .selector,
                actionId,
                uint256(0),
                address(target),
                address(newDestination)
            )
        );
        queue.executeQueuedAction(actionId);

        assertEq(
            queue.pendingActionId(_scopedKey(address(target), KEY_A)),
            actionId,
            "original destination key remains held"
        );
        assertEq(target.configState(KEY_A), 10, "original destination unchanged");
        assertFalse(queue.getQueuedAction(actionId).executed, "action remains pending");
    }

    function test_executeQueuedAction_givenAnyMultiKeyDependencyDrifts_revertsBeforeDispatch()
        public
    {
        uint64 actionId = queue.queueConfig(_keys(KEY_A, KEY_B), _values(11, 22), 1);
        bytes32 scopedKeyB = _scopedKey(KEY_B);
        target.setConfigState(KEY_B, 99);
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                uint256(0),
                scopedKeyB,
                keccak256(abi.encode(KEY_B, uint256(20))),
                keccak256(abi.encode(KEY_B, uint256(99)))
            )
        );
        queue.executeQueuedAction(actionId);

        assertEq(target.executionOrderLength(), 0, "dispatch not entered");
        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), actionId, "first key remains held");
        assertEq(queue.pendingActionId(scopedKeyB), actionId, "drifted key remains held");
    }

    function test_givenLaterSubActionStateDrift_executeQueuedAction_rollsBackEarlierDispatch()
        public
    {
        uint64 actionId = queue.queueBatch(_batch(KEY_A, KEY_B));
        target.setConfigState(KEY_B, 99);
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                uint256(1),
                _scopedKey(KEY_B),
                keccak256(abi.encode(KEY_B, uint256(20))),
                keccak256(abi.encode(KEY_B, uint256(99)))
            )
        );
        queue.executeQueuedAction(actionId);

        assertEq(target.configState(KEY_A), 10, "earlier target write rolled back");
        assertEq(target.configState(KEY_B), 99, "out-of-band drift retained");
        assertEq(target.executionOrderLength(), 0, "execution log rolled back");
        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), actionId, "earlier key remains held");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), actionId, "drifted key remains held");
        assertFalse(queue.getQueuedAction(actionId).executed, "action remains pending");
    }

    function test_givenTransitiveDependencyAcrossKeys_executeQueuedAction_revertsAtomically()
        public
    {
        queue.setStateHashDependency(KEY_B, KEY_A);
        uint64 actionId = queue.queueBatch(_batch(KEY_A, KEY_B));
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                uint256(1),
                _scopedKey(KEY_B),
                keccak256(abi.encode(KEY_B, uint256(10))),
                keccak256(abi.encode(KEY_B, uint256(11)))
            )
        );
        queue.executeQueuedAction(actionId);

        assertEq(target.configState(KEY_A), 10, "dependency write rolled back");
        assertEq(target.configState(KEY_B), 20, "dependent state unchanged");
        assertEq(target.executionOrderLength(), 0, "execution log rolled back");
        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), actionId, "dependency key remains held");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), actionId, "dependent key remains held");
        assertFalse(queue.getQueuedAction(actionId).executed, "action remains pending");
    }

    function test_executeQueuedAction_givenLaterDispatchReverts_rollsBackTargetsAndGuards() public {
        uint64 actionId = queue.queueBatch(_batch(KEY_A, KEY_B));
        target.setRevertMarker(2);
        _warpReady(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(MockConfigTarget.MockConfigTarget_ExecutionReverted.selector, 2)
        );
        queue.executeQueuedAction(actionId);

        assertEq(target.configState(KEY_A), 10, "first target write rolled back");
        assertEq(target.configState(KEY_B), 20, "second target unchanged");
        assertEq(target.executionOrderLength(), 0, "execution log rolled back");
        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), actionId, "first key remains held");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), actionId, "second key remains held");
    }

    function test_executeQueuedAction_releasesAllKeysOnlyAfterWholeBatchCompletes() public {
        uint64 actionId = queue.queueBatch(_batch(KEY_A, KEY_B));
        target.setReentry(address(queue), KEY_A);
        target.setReentryMarker(2);
        _warpReady(actionId);

        queue.executeQueuedAction(actionId);

        assertTrue(target.reentryAttempted(), "reentry attempted");
        assertFalse(target.reentrySucceeded(), "held key blocks reentry");
        assertEq(queue.nextActionId(), 2, "reentrant queue did not consume action id");
        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "first key released at completion");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), 0, "second key released at completion");
        assertEq(target.configState(KEY_A), 11, "first config applied");
        assertEq(target.configState(KEY_B), 22, "second config applied");
    }

    function test_executeQueuedAction_releasesEveryKeyAndClearsEveryGuard() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = queue.makeAction(_keys(KEY_A, KEY_B), _values(11, 22), 1);
        actions[1] = queue.makeAction(_keys(KEY_C), _values(33), 2);
        uint64 actionId = queue.queueBatch(actions);
        _warpReady(actionId);

        queue.executeQueuedAction(actionId);

        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "first key released");
        assertEq(queue.pendingActionId(_scopedKey(KEY_B)), 0, "second key released");
        assertEq(queue.pendingActionId(_scopedKey(KEY_C)), 0, "third key released");
        assertEq(queue.getQueuedConfigStateCount(actionId, 0), 0, "first guards cleared");
        assertEq(queue.getQueuedConfigStateCount(actionId, 1), 0, "second guards cleared");
    }

    function test_givenReleasedKey_executeQueuedAction_allowsKeyToBeQueuedAgain() public {
        uint64 executedActionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        _warpReady(executedActionId);
        queue.executeQueuedAction(executedActionId);

        uint64 replacementActionId = queue.queueConfig(_keys(KEY_A), _values(12), 2);

        assertEq(
            queue.pendingActionId(_scopedKey(KEY_A)),
            replacementActionId,
            "replacement owns released key"
        );
        assertEq(replacementActionId, executedActionId + 1, "replacement action id");
    }

    function test_executeQueuedAction_givenOwnershipMismatch_revertsWithoutDeletingForeignLock()
        public
    {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        uint64 corruptOwner = 99;
        bytes32 scopedKey = _scopedKey(KEY_A);
        vm.store(address(queue), _pendingActionIdSlot(scopedKey), bytes32(uint256(corruptOwner)));
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
        queue.executeQueuedAction(actionId);

        assertEq(queue.pendingActionId(scopedKey), corruptOwner, "foreign owner retained");
        assertFalse(queue.getQueuedAction(actionId).executed, "action remains pending");
    }

    function _pendingActionIdSlot(bytes32 key_) internal pure returns (bytes32 slot) {
        return keccak256(abi.encode(key_, uint256(2)));
    }
}
