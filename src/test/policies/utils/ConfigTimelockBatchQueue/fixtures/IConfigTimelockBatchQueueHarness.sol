// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

interface IConfigTimelockBatchQueueHarness {
    function queueConfig(
        bytes32[] memory keys_,
        uint256[] memory values_,
        uint256 marker_
    ) external returns (uint64 actionId);
}
