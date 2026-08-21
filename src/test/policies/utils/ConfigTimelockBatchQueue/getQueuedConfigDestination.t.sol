// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";

contract ConfigTimelockBatchQueueGetQueuedConfigDestinationTest is ConfigTimelockBatchQueueTest {
    function test_getQueuedConfigDestination_returnsQueueTimeDestination() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        assertEq(
            _queue.getQueuedConfigDestination(actionId, 0),
            address(_target),
            "queue-time destination"
        );
    }

    function test_getQueuedConfigDestination_afterExecution_returnsZero() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        _warpReady(actionId);
        _queue.executeQueuedAction(actionId);
        assertEq(
            _queue.getQueuedConfigDestination(actionId, 0),
            address(0),
            "executed destination cleared"
        );
    }

    function test_getQueuedConfigDestination_afterCancellation_returnsZero() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        _queue.cancelQueuedAction(actionId);
        assertEq(
            _queue.getQueuedConfigDestination(actionId, 0),
            address(0),
            "cancelled destination cleared"
        );
    }
}
