// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Inventory timelock templates. Queue, execute and emergency cancel are separate runs.
/// @dev Target selector admission and execution-time commitments remain enforced by the queue.
contract BurnerLoansInventoryConfigTimelockBatch is BatchScriptV2 {
    /// @notice Queue BurnSurplus using the required args file.
    function queueBurnSurplus(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansInventoryConfigTimelock"),
            abi.encodeCall(IBurnerLoansInventoryConfigTimelock.queueBurnSurplus, ())
        );
        proposeBatch();
    }

    /// @notice Queue RescueSurplus using the required args file.
    function queueRescueSurplus(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansInventoryConfigTimelock"),
            abi.encodeCall(IBurnerLoansInventoryConfigTimelock.queueRescueSurplus, ())
        );
        proposeBatch();
    }

    function executeQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansInventoryConfigTimelock"),
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
            _envAddressNotZero("olympus.policies.BurnerLoansInventoryConfigTimelock"),
            abi.encodeCall(
                ITimelockBatchQueue.cancelQueuedAction,
                (SafeCast.toUint64(_readBatchArgUint256("cancelQueuedAction", "actionId")))
            )
        );
        proposeBatch();
    }
}
