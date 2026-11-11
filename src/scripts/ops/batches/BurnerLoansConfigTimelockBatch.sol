// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Config timelock templates. Queue, execute and emergency cancel are separate runs.
/// @dev Target selector admission and execution-time commitments remain enforced by the queue.
contract BurnerLoansConfigTimelockBatch is BatchScriptV2 {
    using SafeCast for uint256;

    /// @notice Queue SetAssetDebtCap using the required args file.
    function queueSetAssetDebtCap(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansConfigTimelock.queueSetAssetDebtCap,
                (
                    _readBatchArgAddress("queueSetAssetDebtCap", "asset"),
                    _readBatchArgUint256("queueSetAssetDebtCap", "debtCapOhm").toUint128()
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue SetAssetWithdrawAsShares using the required args file.
    function queueSetAssetWithdrawAsShares(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansConfigTimelock.queueSetAssetWithdrawAsShares,
                (
                    _readBatchArgAddress("queueSetAssetWithdrawAsShares", "asset"),
                    _readBatchArgBool("queueSetAssetWithdrawAsShares", "withdrawAsShares")
                )
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
            _envAddressNotZero("olympus.policies.BurnerLoansConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansConfigTimelock.queueRescue,
                (
                    _readBatchArgAddress("queueRescue", "token"),
                    _readBatchArgAddress("queueRescue", "destination")
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue SetAssetFeeConfig using the required args file.
    function queueSetAssetFeeConfig(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansConfigTimelock.queueSetAssetFeeConfig,
                (
                    _readBatchArgAddress("queueSetAssetFeeConfig", "asset"),
                    IBurnerLoansRisk.AssetFeeConfig(
                        _readBatchArgUint256("queueSetAssetFeeConfig", "baseFeeBps").toUint16(),
                        _readBatchArgUint256("queueSetAssetFeeConfig", "kinkBps").toUint16(),
                        _readBatchArgUint256("queueSetAssetFeeConfig", "preKinkSlopeBps")
                            .toUint16(),
                        _readBatchArgUint256("queueSetAssetFeeConfig", "postKinkSlopeBps")
                            .toUint16()
                    )
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue SetAssetRiskConfig using the required args file.
    function queueSetAssetRiskConfig(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansConfigTimelock.queueSetAssetRiskConfig,
                (
                    _readBatchArgAddress("queueSetAssetRiskConfig", "asset"),
                    IBurnerLoansRisk.AssetRiskConfigInput(
                        _readBatchArgUint256("queueSetAssetRiskConfig", "maxLtvBps").toUint16(),
                        _readBatchArgUint256("queueSetAssetRiskConfig", "backingMultiplierBps")
                            .toUint16(),
                        _readBatchArgUint256("queueSetAssetRiskConfig", "keeperRewardBps")
                            .toUint16(),
                        _readBatchArgUint256("queueSetAssetRiskConfig", "termLength").toUint48(),
                        _readBatchArgUint256("queueSetAssetRiskConfig", "maxMaturityHorizon")
                            .toUint48(),
                        _readBatchArgUint256("queueSetAssetRiskConfig", "maxKeeperReward")
                            .toUint128()
                    )
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
            _envAddressNotZero("olympus.policies.BurnerLoansConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansConfigTimelock.queueBatch,
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
            _envAddressNotZero("olympus.policies.BurnerLoansConfigTimelock"),
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
            _envAddressNotZero("olympus.policies.BurnerLoansConfigTimelock"),
            abi.encodeCall(
                ITimelockBatchQueue.cancelQueuedAction,
                (SafeCast.toUint64(_readBatchArgUint256("cancelQueuedAction", "actionId")))
            )
        );
        proposeBatch();
    }
}
