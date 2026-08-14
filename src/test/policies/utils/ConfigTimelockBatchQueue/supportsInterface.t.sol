// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";

import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";

contract ConfigTimelockBatchQueueSupportsInterfaceTest is ConfigTimelockBatchQueueTest {
    function test_supportsInterface_reportsQueueCapabilities() public view {
        assertTrue(queue.supportsInterface(type(IERC165).interfaceId), "ERC-165 supported");
        assertTrue(
            queue.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "batch queue supported"
        );
        assertTrue(
            queue.supportsInterface(type(IConfigTimelockBatchQueue).interfaceId),
            "config queue supported"
        );
    }
}
