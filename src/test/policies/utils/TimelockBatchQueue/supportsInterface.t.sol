// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";

contract TimelockBatchQueueSupportsInterfaceTest is TimelockBatchQueueTest {
    function test_supportsInterface_reportsExpectedInterfaces() public view {
        ERC165Helper.validateSupportsInterface(address(queue));
        assertTrue(queue.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(
            queue.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "ITimelockBatchQueue"
        );
        assertFalse(queue.supportsInterface(type(IERC20).interfaceId), "IERC20");
    }
}
