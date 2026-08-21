// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";

contract ConfigTimelockBatchQueuePendingActionIdTest is ConfigTimelockBatchQueueTest {
    function test_pendingActionId_givenFreeKey_returnsZero() public view {
        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "free key has no owner");
    }

    function test_pendingActionId_givenReservedKey_returnsOwner() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), actionId, "reserved key owner");
    }

    function test_pendingActionId_givenExecutedAction_returnsZero() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        _warpReady(actionId);
        queue.executeQueuedAction(actionId);
        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "executed key released");
    }

    function test_pendingActionId_givenCancelledAction_returnsZero() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        queue.cancelQueuedAction(actionId);
        assertEq(queue.pendingActionId(_scopedKey(KEY_A)), 0, "cancelled key released");
    }
}
