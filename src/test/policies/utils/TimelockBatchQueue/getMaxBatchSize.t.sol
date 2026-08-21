// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";

contract TimelockBatchQueueGetMaxBatchSizeTest is TimelockBatchQueueTest {
    function test_getMaxBatchSize_returnsDefault() public view {
        assertEq(queue.getMaxBatchSize(), 15);
    }

    function test_getMaxBatchSize_returnsOverride() public {
        queue.setMaxBatchSizeOverride(3);
        assertEq(queue.getMaxBatchSize(), 3);
    }
}
