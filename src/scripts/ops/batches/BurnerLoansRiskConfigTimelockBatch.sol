// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Risk timelock templates. Queue, execute and emergency cancel are separate runs.
/// @dev Target selector admission and execution-time commitments remain enforced by the queue.
contract BurnerLoansRiskConfigTimelockBatch is BatchScriptV2 {
    using SafeCast for uint256;

    /// @notice Queue SetReferralFeeBps using the required args file.
    function queueSetReferralFeeBps(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansRiskConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansRiskConfigTimelock.queueSetReferralFeeBps,
                (_readBatchArgUint256("queueSetReferralFeeBps", "bps").toUint16())
            )
        );
        proposeBatch();
    }

    /// @notice Queue SetReferrerAllowed using the required args file.
    function queueSetReferrerAllowed(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansRiskConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansRiskConfigTimelock.queueSetReferrerAllowed,
                (
                    _readBatchArgAddress("queueSetReferrerAllowed", "referrer"),
                    _readBatchArgBool("queueSetReferrerAllowed", "allowed")
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue SetPriceCacheMaxAge using the required args file.
    function queueSetPriceCacheMaxAge(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansRiskConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansRiskConfigTimelock.queueSetPriceCacheMaxAge,
                (_readBatchArgUint256("queueSetPriceCacheMaxAge", "age").toUint48())
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
            _envAddressNotZero("olympus.policies.BurnerLoansRiskConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansRiskConfigTimelock.queueBatch,
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
            _envAddressNotZero("olympus.policies.BurnerLoansRiskConfigTimelock"),
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
            _envAddressNotZero("olympus.policies.BurnerLoansRiskConfigTimelock"),
            abi.encodeCall(
                ITimelockBatchQueue.cancelQueuedAction,
                (SafeCast.toUint64(_readBatchArgUint256("cancelQueuedAction", "actionId")))
            )
        );
        proposeBatch();
    }
}
