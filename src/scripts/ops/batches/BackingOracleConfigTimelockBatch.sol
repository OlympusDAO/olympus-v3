// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracleConfigTimelock} from "src/policies/interfaces/IBackingOracleConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Delayed backing updates use backing_admin; execute and emergency cancel are separate runs.
contract BackingOracleConfigTimelockBatch is BatchScriptV2 {
    function queueSetBacking(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BackingOracleConfigTimelock"),
            abi.encodeCall(
                IBackingOracleConfigTimelock.queueSetBacking,
                (_readBatchArgUint256("queueSetBacking", "backing"))
            )
        );
        proposeBatch();
    }

    // Actual queue execution validates existence, delay, state commitments and terminal state.
    // forge-lint: disable-next-item(calls-loop)

    function executeQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BackingOracleConfigTimelock"),
            abi.encodeCall(
                ITimelockBatchQueue.executeQueuedAction,
                (SafeCast.toUint64(_readBatchArgUint256("executeQueuedAction", "actionId")))
            )
        );
        proposeBatch();
    }

    function cancelQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUpWithEmergencyMS(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BackingOracleConfigTimelock"),
            abi.encodeCall(
                ITimelockBatchQueue.cancelQueuedAction,
                (SafeCast.toUint64(_readBatchArgUint256("cancelQueuedAction", "actionId")))
            )
        );
        proposeBatch();
    }
}
