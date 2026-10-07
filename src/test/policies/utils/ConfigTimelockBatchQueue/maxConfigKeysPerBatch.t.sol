// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";

contract ConfigTimelockBatchQueueMaxConfigKeysPerBatchTest is ConfigTimelockBatchQueueTest {
    function test_maxConfigKeysPerBatch_returnsOverride() public view {
        assertEq(_queue.maxConfigKeysPerBatch(), 4, "configured maximum");
    }

    function test_maxConfigKeysPerBatch_defaultsToMaximumBatchSize() public {
        _queue.setMaxConfigKeys(0);
        assertEq(_queue.maxConfigKeysPerBatch(), 15, "default maximum batch size");
    }
}
