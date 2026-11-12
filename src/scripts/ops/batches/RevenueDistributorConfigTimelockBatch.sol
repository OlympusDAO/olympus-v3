// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {console2} from "@forge-std-1.16.2/console2.sol";
import {TimelockBatchScript} from "src/scripts/ops/lib/TimelockBatchScript.sol";

/// @notice Reviewed args files supply distributor configuration and actual queued action IDs.
contract RevenueDistributorConfigTimelockBatch is TimelockBatchScript {
    using SafeCast for uint256;

    /// @notice Submit the reviewed queueDisableAssetRoutes inputs to the delayed queue.
    function queueDisableAssetRoutes(
        bool useDaoMS_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_
    ) external setUp(useDaoMS_, argsFile_, ledgerDerivationPath_) {
        console2.log("RevenueDistributorConfigTimelockBatch: queueDisableAssetRoutes");
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
        console2.log("RevenueDistributorConfigTimelockBatch: queueSetYieldRecipient");
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
        console2.log("RevenueDistributorConfigTimelockBatch: queueRescue");
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
        console2.log("RevenueDistributorConfigTimelockBatch: queueRescuePendingPayout");
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
        console2.log("RevenueDistributorConfigTimelockBatch: queueSetAssetRoutes");
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
        console2.log("RevenueDistributorConfigTimelockBatch: queueBatch");
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

    function _timelockKey() internal pure override returns (string memory) {
        return "olympus.policies.RevenueDistributorConfigTimelock";
    }
}
