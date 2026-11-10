// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Payout timelock templates. Queue, execute and emergency cancel are separate runs.
/// @dev Target selector admission and execution-time commitments remain enforced by the queue.
contract BurnerLoansPayoutConfigTimelockBatch is BatchScriptV2 {
    using SafeCast for uint256;

    /// @notice Queue SetSendFeesToDistributor using the required args file.
    function queueSetSendFeesToDistributor(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansPayoutConfigTimelock.queueSetSendFeesToDistributor,
                (_readBatchArgBool("queueSetSendFeesToDistributor", "enabled"))
            )
        );
        proposeBatch();
    }

    /// @notice Queue SetSendYieldToDistributor using the required args file.
    function queueSetSendYieldToDistributor(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansPayoutConfigTimelock.queueSetSendYieldToDistributor,
                (_readBatchArgBool("queueSetSendYieldToDistributor", "enabled"))
            )
        );
        proposeBatch();
    }

    /// @notice Queue Rescue using the required args file.
    function queueRescue(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansPayoutConfigTimelock.queueRescue,
                (
                    _readBatchArgAddress("queueRescue", "token"),
                    _readBatchArgAddress("queueRescue", "destination")
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue RescuePendingPayout using the required args file.
    function queueRescuePendingPayout(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansPayoutConfigTimelock.queueRescuePendingPayout,
                (
                    _readBatchArgAddress("queueRescuePendingPayout", "token"),
                    _readBatchArgAddress("queueRescuePendingPayout", "recipient"),
                    _readBatchArgAddress("queueRescuePendingPayout", "destination"),
                    _readBatchArgUint256("queueRescuePendingPayout", "amount")
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue Batch using the required args file.
    function queueBatch(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansPayoutConfigTimelock.queueBatch,
                (
                    abi.decode(
                        vm.parseBytes(_readBatchArgString("queueBatch", "encodedActions")),
                        (ITimelockBatchQueue.BatchAction[])
                    )
                )
            )
        );
        proposeBatch();
    }

    function executeQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
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
            _envAddressNotZero("olympus.policies.BurnerLoansPayoutConfigTimelock"),
            abi.encodeCall(
                ITimelockBatchQueue.cancelQueuedAction,
                (SafeCast.toUint64(_readBatchArgUint256("cancelQueuedAction", "actionId")))
            )
        );
        proposeBatch();
    }
}
