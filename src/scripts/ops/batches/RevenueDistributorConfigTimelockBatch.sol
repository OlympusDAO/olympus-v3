// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";

/// @notice Reviewed args files supply distributor configuration and actual queued action IDs.
contract RevenueDistributorConfigTimelockBatch is BatchScriptV2 {
    using SafeCast for uint256;

    /// @notice Submit the reviewed queueDisableAssetRoutes inputs to the delayed queue.
    function queueDisableAssetRoutes(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.RevenueDistributorConfigTimelock"),
            abi.encodeCall(
                IRevenueDistributorConfigTimelock.queueDisableAssetRoutes,
                (_readBatchArgAddress("queueDisableAssetRoutes", "asset"))
            )
        );
        proposeBatch();
    }

    /// @notice Submit the reviewed queueSetYieldRecipient inputs to the delayed queue.
    function queueSetYieldRecipient(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.RevenueDistributorConfigTimelock"),
            abi.encodeCall(
                IRevenueDistributorConfigTimelock.queueSetYieldRecipient,
                (_readBatchArgAddress("queueSetYieldRecipient", "recipient"))
            )
        );
        proposeBatch();
    }

    /// @notice Submit the reviewed queueRescue inputs to the delayed queue.
    function queueRescue(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.RevenueDistributorConfigTimelock"),
            abi.encodeCall(
                IRevenueDistributorConfigTimelock.queueRescue,
                (
                    _readBatchArgAddress("queueRescue", "asset"),
                    _readBatchArgAddress("queueRescue", "destination")
                )
            )
        );
        proposeBatch();
    }

    /// @notice Submit the reviewed queueRescuePendingPayout inputs to the delayed queue.
    function queueRescuePendingPayout(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.RevenueDistributorConfigTimelock"),
            abi.encodeCall(
                IRevenueDistributorConfigTimelock.queueRescuePendingPayout,
                (
                    _readBatchArgAddress("queueRescuePendingPayout", "asset"),
                    _readBatchArgAddress("queueRescuePendingPayout", "recipient"),
                    _readBatchArgAddress("queueRescuePendingPayout", "destination"),
                    _readBatchArgUint256("queueRescuePendingPayout", "amount")
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue a complete route; omitted basis points accrue to Treasury.
    function queueSetAssetRoutes(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        IRevenueDistributor.AssetRoute[] memory routes = abi.decode(
            vm.parseBytes(_readBatchArgString("queueSetAssetRoutes", "encodedRoutes")),
            (IRevenueDistributor.AssetRoute[])
        );
        addToBatch(
            _envAddressNotZero("olympus.policies.RevenueDistributorConfigTimelock"),
            abi.encodeCall(
                IRevenueDistributorConfigTimelock.queueSetAssetRoutes,
                (
                    _readBatchArgAddress("queueSetAssetRoutes", "asset"),
                    _readBatchArgUint256("queueSetAssetRoutes", "repurchaseBps").toUint16(),
                    routes
                )
            )
        );
        proposeBatch();
    }

    /// @notice Queue compatible distributor updates atomically using reviewed selector/payload pairs.
    function queueBatch(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        ITimelockBatchQueue.BatchAction[] memory actions = abi.decode(
            vm.parseBytes(_readBatchArgString("queueBatch", "encodedActions")),
            (ITimelockBatchQueue.BatchAction[])
        );
        addToBatch(
            _envAddressNotZero("olympus.policies.RevenueDistributorConfigTimelock"),
            abi.encodeCall(IRevenueDistributorConfigTimelock.queueBatch, (actions))
        );
        proposeBatch();
    }

    /// @notice Permissionless execution of real action IDs after the notice period.

    /// @notice Emergency cancellation of real action IDs, including while paused.

    function executeQueuedAction(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        addToBatch(
            _envAddressNotZero("olympus.policies.RevenueDistributorConfigTimelock"),
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
            _envAddressNotZero("olympus.policies.RevenueDistributorConfigTimelock"),
            abi.encodeCall(
                ITimelockBatchQueue.cancelQueuedAction,
                (SafeCast.toUint64(_readBatchArgUint256("cancelQueuedAction", "actionId")))
            )
        );
        proposeBatch();
    }
}
