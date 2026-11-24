// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {TimelockBatchScript} from "src/scripts/ops/lib/TimelockBatchScript.sol";

/// @notice Config timelock templates. Queue, execute and emergency cancel are separate runs.
/// @dev Target selector admission and execution-time commitments remain enforced by the queue.
contract BurnerLoansConfigTimelockBatch is TimelockBatchScript {
    using SafeCast for uint256;

    /// @notice Queue SetAssetDebtCap using the required args file.
    function queueSetAssetDebtCap(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("BurnerLoansConfigTimelockBatch: queueSetAssetDebtCap");
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
        console2.log("BurnerLoansConfigTimelockBatch: queueSetAssetWithdrawAsShares");
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
        console2.log("BurnerLoansConfigTimelockBatch: queueRescue");
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
        console2.log("BurnerLoansConfigTimelockBatch: queueSetAssetFeeConfig");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansConfigTimelock.queueSetAssetFeeConfig,
                (
                    _readBatchArgAddress("queueSetAssetFeeConfig", "asset"),
                    IBurnerLoansRisk.AssetFeeConfig({
                        baseFeeBps: _readBatchArgUint256("queueSetAssetFeeConfig", "baseFeeBps")
                            .toUint16(),
                        kinkBps: _readBatchArgUint256("queueSetAssetFeeConfig", "kinkBps")
                            .toUint16(),
                        preKinkSlopeBps: _readBatchArgUint256(
                            "queueSetAssetFeeConfig",
                            "preKinkSlopeBps"
                        ).toUint16(),
                        postKinkSlopeBps: _readBatchArgUint256(
                            "queueSetAssetFeeConfig",
                            "postKinkSlopeBps"
                        ).toUint16()
                    })
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
        console2.log("BurnerLoansConfigTimelockBatch: queueSetAssetRiskConfig");
        addToBatch(
            _envAddressNotZero("olympus.policies.BurnerLoansConfigTimelock"),
            abi.encodeCall(
                IBurnerLoansConfigTimelock.queueSetAssetRiskConfig,
                (
                    _readBatchArgAddress("queueSetAssetRiskConfig", "asset"),
                    IBurnerLoansRisk.AssetRiskConfigInput({
                        maxLtvBps: _readBatchArgUint256("queueSetAssetRiskConfig", "maxLtvBps")
                            .toUint16(),
                        backingMultiplierBps: _readBatchArgUint256(
                            "queueSetAssetRiskConfig",
                            "backingMultiplierBps"
                        ).toUint16(),
                        keeperRewardBps: _readBatchArgUint256(
                            "queueSetAssetRiskConfig",
                            "keeperRewardBps"
                        ).toUint16(),
                        termLength: _readBatchArgUint256("queueSetAssetRiskConfig", "termLength")
                            .toUint48(),
                        maxMaturityHorizon: _readBatchArgUint256(
                            "queueSetAssetRiskConfig",
                            "maxMaturityHorizon"
                        ).toUint48(),
                        maxKeeperReward: _readBatchArgUint256(
                            "queueSetAssetRiskConfig",
                            "maxKeeperReward"
                        ).toUint128()
                    })
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
        console2.log("BurnerLoansConfigTimelockBatch: queueBatch");
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

    function _timelockKey() internal pure override returns (string memory) {
        return "olympus.policies.BurnerLoansConfigTimelock";
    }
}
