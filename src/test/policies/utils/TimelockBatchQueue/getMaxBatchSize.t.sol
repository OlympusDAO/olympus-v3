// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";

contract TimelockBatchQueueGetMaxBatchSizeTest is TimelockBatchQueueTest {
    function test_getMaxBatchSize_returnsDefault() public view {
        // TimelockBatchQueue._maxBatchSize() defaults to 15 sub-actions.
        assertEq(queue.getMaxBatchSize(), 15, "default max batch size");
    }

    function test_getMaxBatchSize_returnsOverride() public {
        queue.setMaxBatchSizeOverride(3);
        assertEq(queue.getMaxBatchSize(), 3, "overridden max batch size");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
