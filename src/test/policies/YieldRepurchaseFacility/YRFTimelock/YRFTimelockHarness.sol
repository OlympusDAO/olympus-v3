// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import {Kernel} from "src/Kernel.sol";
import {YRFTimelock} from "src/policies/YieldRepurchaseFacility/YRFTimelock.sol";

/// @notice Exposes the internal per-sub-action bookkeeping of `YRFTimelock` so that tests
///         can assert that the pre-state bindings and pending parameter slots are recorded
///         at queue time and cleared again on execution and cancellation, which is not
///         fully observable through the public surface.
contract YRFTimelockHarness is YRFTimelock {
    constructor(
        Kernel kernel_,
        uint48 initialTimelockDelay_,
        uint32 gracePeriod_
    ) YRFTimelock(kernel_, initialTimelockDelay_, gracePeriod_) {}

    function expectedPreStateHash(
        uint64 actionId_,
        uint256 index_
    ) external view returns (bytes32) {
        return _expectedPreStateHashes[actionId_][index_];
    }

    function lockKey(uint64 actionId_, uint256 index_) external view returns (bytes32) {
        return _lockKeys[actionId_][index_];
    }

    function pendingActionId(bytes32 lockKey_) external view returns (uint64) {
        return _pendingActionIds[lockKey_];
    }
}
