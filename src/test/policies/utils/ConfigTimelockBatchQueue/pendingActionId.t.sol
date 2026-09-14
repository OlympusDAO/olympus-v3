// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";

contract ConfigTimelockBatchQueuePendingActionIdTest is ConfigTimelockBatchQueueTest {
    function test_pendingActionId_givenFreeKey_returnsZero() public view {
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "free key has no owner");
    }

    function test_pendingActionId_givenReservedKey_returnsOwner() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), actionId, "reserved key owner");
    }

    function test_pendingActionId_givenExecutedAction_returnsZero() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        _warpReady(actionId);
        _queue.executeQueuedAction(actionId);
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "executed key released");
    }

    function test_pendingActionId_givenCancelledAction_returnsZero() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        _queue.cancelQueuedAction(actionId);
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "cancelled key released");
    }
}
