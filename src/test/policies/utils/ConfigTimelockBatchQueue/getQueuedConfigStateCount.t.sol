// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";

contract ConfigTimelockBatchQueueGetQueuedConfigStateCountTest is ConfigTimelockBatchQueueTest {
    function test_getQueuedConfigStateCount_returnsCountPerSubAction() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A, KEY_B, KEY_C), _values(11, 22, 33), 1);
        assertEq(queue.getQueuedConfigStateCount(actionId, 0), 3, "stored guard count");
        assertEq(queue.getQueuedConfigStateCount(actionId, 1), 0, "unknown sub-action count");
    }

    function test_getQueuedConfigStateCount_afterExecution_returnsZero() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        _warpReady(actionId);
        queue.executeQueuedAction(actionId);
        assertEq(queue.getQueuedConfigStateCount(actionId, 0), 0, "executed guards cleared");
    }

    function test_getQueuedConfigStateCount_afterCancellation_returnsZero() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        queue.cancelQueuedAction(actionId);
        assertEq(queue.getQueuedConfigStateCount(actionId, 0), 0, "cancelled guards cleared");
    }
}
