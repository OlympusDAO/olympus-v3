// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";

contract ConfigTimelockBatchQueueGetQueuedConfigDestinationTest is ConfigTimelockBatchQueueTest {
    function test_getQueuedConfigDestination_returnsQueueTimeDestination() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        assertEq(
            queue.getQueuedConfigDestination(actionId, 0),
            address(target),
            "queue-time destination"
        );
    }

    function test_getQueuedConfigDestination_afterExecution_returnsZero() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        _warpReady(actionId);
        queue.executeQueuedAction(actionId);
        assertEq(
            queue.getQueuedConfigDestination(actionId, 0),
            address(0),
            "executed destination cleared"
        );
    }

    function test_getQueuedConfigDestination_afterCancellation_returnsZero() public {
        uint64 actionId = queue.queueConfig(_keys(KEY_A), _values(11), 1);
        queue.cancelQueuedAction(actionId);
        assertEq(
            queue.getQueuedConfigDestination(actionId, 0),
            address(0),
            "cancelled destination cleared"
        );
    }
}
