// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IConfigTimelockBatchQueueHarness} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/IConfigTimelockBatchQueueHarness.sol";

// Test fixtures accept zero addresses to model unset, cleared, and invalid states.
// forge-lint: disable-start(missing-zero-check)

contract MockConfigTarget {
    uint256 internal constant _REENTRY_MARKER = 999;

    error MockConfigTarget_ExecutionReverted(uint256 marker);

    mapping(bytes32 key => uint256 value) public configState;
    uint256[] public executionOrder;

    uint256 public revertMarker;
    address public reentryQueue;
    bytes32 public reentryKey;
    uint256 public reentryMarker;
    bool public reentryAttempted;
    bool public reentrySucceeded;

    function setConfigState(bytes32 key_, uint256 value_) external {
        configState[key_] = value_;
    }

    function setRevertMarker(uint256 marker_) external {
        revertMarker = marker_;
    }

    function setReentry(address queue_, bytes32 key_) external {
        reentryQueue = queue_;
        reentryKey = key_;
    }

    function setReentryMarker(uint256 marker_) external {
        reentryMarker = marker_;
    }

    function executionOrderLength() external view returns (uint256 length) {
        return executionOrder.length;
    }

    function applyConfig(
        bytes32[] memory keys_,
        uint256[] memory values_,
        uint256 marker_
    ) external {
        if (marker_ == revertMarker) revert MockConfigTarget_ExecutionReverted(marker_);

        if (reentryQueue != address(0) && (reentryMarker == 0 || reentryMarker == marker_)) {
            reentryAttempted = true;
            bytes32[] memory reentryKeys = new bytes32[](1);
            reentryKeys[0] = reentryKey;
            uint256[] memory reentryValues = new uint256[](1);
            reentryValues[0] = _REENTRY_MARKER;
            // The fixture records reentry failure without reverting the outer call.
            // forge-lint: disable-start(low-level-calls)
            (reentrySucceeded, ) = reentryQueue.call(
                abi.encodeCall(
                    IConfigTimelockBatchQueueHarness.queueConfig,
                    (reentryKeys, reentryValues, _REENTRY_MARKER)
                )
            );
            // forge-lint: disable-end(low-level-calls)
        }

        uint256 len = keys_.length;
        for (uint256 i; i < len; ++i) {
            configState[keys_[i]] = values_[i];
        }
        executionOrder.push(marker_);
    }
}

// forge-lint: disable-end(missing-zero-check)
