// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockQueue} from "src/policies/interfaces/utils/ITimelockQueue.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Common execution and emergency cancellation for single-action and batch configuration timelocks.
abstract contract TimelockBatchScript is BatchScriptV2 {
    /// @dev Each concrete script selects its queue from the chain environment.
    function _timelockKey() internal pure virtual returns (string memory);

    /// @notice Execute an existing action after its notice period; queue guards remain authoritative.
    function executeQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        address queue = _envAddressNotZero(_timelockKey());
        uint64 actionId = SafeCast.toUint64(
            _readBatchArgUint256("executeQueuedAction", "actionId")
        );
        console2.log("Executing queued action", actionId);
        console2.log("Timelock", queue);
        addToBatch(queue, abi.encodeCall(ITimelockQueue.executeQueuedAction, (actionId)));
        proposeBatch();
    }

    /// @notice Cancel an existing action through the Emergency multisig, including while paused.
    function cancelQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        address queue = _envAddressNotZero(_timelockKey());
        uint64 actionId = SafeCast.toUint64(_readBatchArgUint256("cancelQueuedAction", "actionId"));
        console2.log("Cancelling queued action", actionId);
        console2.log("Timelock", queue);
        addToBatch(queue, abi.encodeCall(ITimelockQueue.cancelQueuedAction, (actionId)));
        proposeBatch();
    }
}
