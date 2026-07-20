// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockCancelQueuedActionBatchTest is BurnerLoansConfigTimelockTest {
    // cancelQueuedAction
    // given a queued batch has multiple sub-actions
    //  when emergency cancels the batch
    //   then the batch is marked cancelled and all sub-actions are cleared
    function test_givenEmergencyCaller_cancelsBatchAndClearsSubActions(uint48 elapsed_) public {
        ITimelockBatchQueue.BatchAction[] memory actions = _cancelledBatch();

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueBatch(actions);
        uint256 queuedAt = block.timestamp;
        elapsed_ = uint48(bound(elapsed_, 0, type(uint48).max));
        vm.warp(queuedAt + elapsed_);

        assertEq(configTimelock.getQueuedActionLength(actionId), 2, "sub-actions before");

        vm.prank(emergency);
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit TimelockActionCancelled(actionId, emergency);
        configTimelock.cancelQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId);
        assertTrue(action.cancelled, "cancelled");
        assertFalse(action.executed, "not executed");
        assertEq(action.actions.length, 0, "sub-actions cleared");

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        configTimelock.getQueuedActionLength(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        configTimelock.executeQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given a queued batch has risk, fee, and debt-cap sub-action state
    //  when emergency cancels the batch
    //   then pre-state and projected post-state storage is cleared for every sub-action
    function test_givenQueuedBatch_clearsStoredStateOnCancellation() public {
        vm.prank(admin);
        burnerLoansConfig.setConfigurator(address(configTimelockHarness));

        ITimelockBatchQueue.BatchAction[] memory actions = _mixedStateBatch();

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelockHarness.queueBatch(actions);

        assertNotEq(
            configTimelockHarness.expectedPreStateHash(actionId, 0),
            bytes32(0),
            "risk pre-state stored"
        );
        assertNotEq(
            configTimelockHarness.expectedPreStateHash(actionId, 1),
            bytes32(0),
            "fee pre-state stored"
        );
        assertNotEq(
            configTimelockHarness.expectedPreStateHash(actionId, 2),
            bytes32(0),
            "debt cap pre-state stored"
        );

        (
            bool assetExists,
            address asset,
            IBurnerLoans.AssetConfig memory assetConfig
        ) = configTimelockHarness.assetConfigPostState(actionId, 0);
        assertTrue(assetExists, "risk post-state stored");
        assertEq(asset, address(usds), "risk asset");
        assertEq(assetConfig.collateralFactorBps, 9_500, "risk post-state collateral factor");

        (
            bool feeExists,
            address feeAsset,
            IBurnerLoans.AssetFeeConfig memory feeConfig
        ) = configTimelockHarness.feeConfigPostState(actionId, 1);
        assertTrue(feeExists, "fee post-state stored");
        assertEq(feeAsset, address(usds), "fee asset");
        assertEq(feeConfig.baseFeeBps, 50, "fee post-state base fee");

        (assetExists, asset, assetConfig) = configTimelockHarness.assetConfigPostState(actionId, 2);
        assertTrue(assetExists, "debt cap post-state stored");
        assertEq(asset, address(usds), "debt cap asset");
        assertEq(assetConfig.debtCap, 200_000e9, "debt cap post-state");

        vm.prank(emergency);
        configTimelockHarness.cancelQueuedAction(actionId);

        assertEq(
            configTimelockHarness.expectedPreStateHash(actionId, 0),
            bytes32(0),
            "risk pre-state cleared"
        );
        assertEq(
            configTimelockHarness.expectedPreStateHash(actionId, 1),
            bytes32(0),
            "fee pre-state cleared"
        );
        assertEq(
            configTimelockHarness.expectedPreStateHash(actionId, 2),
            bytes32(0),
            "debt cap pre-state cleared"
        );

        (assetExists, asset, assetConfig) = configTimelockHarness.assetConfigPostState(actionId, 0);
        assertFalse(assetExists, "risk post-state cleared");
        assertEq(asset, address(0), "risk asset cleared");
        assertEq(assetConfig.collateralFactorBps, 0, "risk config cleared");

        (feeExists, feeAsset, feeConfig) = configTimelockHarness.feeConfigPostState(actionId, 1);
        assertFalse(feeExists, "fee post-state cleared");
        assertEq(feeAsset, address(0), "fee asset cleared");
        assertEq(feeConfig.baseFeeBps, 0, "fee config cleared");

        (assetExists, asset, assetConfig) = configTimelockHarness.assetConfigPostState(actionId, 2);
        assertFalse(assetExists, "debt cap post-state cleared");
        assertEq(asset, address(0), "debt cap asset cleared");
        assertEq(assetConfig.debtCap, 0, "debt cap config cleared");
    }

    // cancelQueuedAction
    // given the latest queued projection is a batch and is cancelled
    //  when a later risk action is queued and executed after the earlier pending risk action
    //   then the later action uses the earlier pending projection, not the cancelled batch state
    function test_givenLatestProjectionBatchCancelled_laterActionUsesEarlierPendingProjection()
        public
    {
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory termUpdate = _termUpdate(14 days);
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection
            memory termSelection = _termSelection();
        ITimelockBatchQueue.BatchAction[] memory cancelledActions = _cancelledBatch();
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory horizonUpdate = _horizonUpdate(
            21 days
        );
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection
            memory horizonSelection = _horizonSelection();

        vm.startPrank(burnerLoansAdmin);
        uint64 termActionId = configTimelock.queueSetAssetRiskConfig(
            address(usds),
            termUpdate,
            termSelection
        );
        uint64 cancelledActionId = configTimelock.queueBatch(cancelledActions);
        vm.stopPrank();

        vm.prank(emergency);
        configTimelock.cancelQueuedAction(cancelledActionId);

        vm.prank(burnerLoansAdmin);
        uint64 horizonActionId = configTimelock.queueSetAssetRiskConfig(
            address(usds),
            horizonUpdate,
            horizonSelection
        );

        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(termActionId);
        configTimelock.executeQueuedAction(horizonActionId);

        IBurnerLoans.AssetConfig memory config = burnerLoans.getAssetConfig(address(usds));
        assertEq(config.termLength, 14 days, "term length");
        assertEq(config.maxMaturityHorizon, 21 days, "max maturity horizon");
        assertEq(config.collateralFactorBps, 10_000, "cancelled batch state not applied");
    }

    function _cancelledBatch()
        internal
        view
        returns (ITimelockBatchQueue.BatchAction[] memory actions)
    {
        actions = new ITimelockBatchQueue.BatchAction[](2);
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory collateralFactorUpdate;
        collateralFactorUpdate.collateralFactorBps = 9_500;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory collateralFactorSelection;
        collateralFactorSelection.collateralFactorBps = true;

        actions[0] = _riskAction(collateralFactorUpdate, collateralFactorSelection);
        actions[1] = _riskAction(_horizonUpdate(60 days), _horizonSelection());
    }

    function _mixedStateBatch()
        internal
        view
        returns (ITimelockBatchQueue.BatchAction[] memory actions)
    {
        actions = new ITimelockBatchQueue.BatchAction[](3);

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory collateralFactorUpdate;
        collateralFactorUpdate.collateralFactorBps = 9_500;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory collateralFactorSelection;
        collateralFactorSelection.collateralFactorBps = true;

        IBurnerLoans.AssetFeeConfig memory feeUpdate;
        feeUpdate.baseFeeBps = 50;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory feeSelection;
        feeSelection.baseFeeBps = true;

        actions[0] = _riskAction(collateralFactorUpdate, collateralFactorSelection);
        actions[1] = _feeAction(feeUpdate, feeSelection);
        actions[2] = _debtCapAction(200_000e9);
    }

    function _riskAction(
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update_,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory action) {
        action = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setAssetRiskConfig.selector,
            payload: abi.encode(address(usds), update_, selection_)
        });
    }

    function _feeAction(
        IBurnerLoans.AssetFeeConfig memory update_,
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory action) {
        action = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setAssetFeeConfig.selector,
            payload: abi.encode(address(usds), update_, selection_)
        });
    }

    function _debtCapAction(
        uint256 debtCapOhm_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory action) {
        action = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: IBurnerLoansConfig.setAssetDebtCap.selector,
            payload: abi.encode(address(usds), debtCapOhm_)
        });
    }

    function _termUpdate(
        uint48 termLength_
    ) internal pure returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update) {
        update.termLength = termLength_;
    }

    function _horizonUpdate(
        uint48 maxMaturityHorizon_
    ) internal pure returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update) {
        update.maxMaturityHorizon = maxMaturityHorizon_;
    }

    function _termSelection()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection)
    {
        selection.termLength = true;
    }

    function _horizonSelection()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection)
    {
        selection.maxMaturityHorizon = true;
    }
}
