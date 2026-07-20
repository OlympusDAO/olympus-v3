// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockExecuteQueuedActionBatchTest is BurnerLoansConfigTimelockTest {
    // executeQueuedAction
    // given a queued batch has two risk sub-actions for the same asset
    //  when the batch is queued
    //   then pre-state and post-state are captured against each intermediate asset config
    function test_givenSameAssetRiskBatch_capturesIntermediatePreAndPostState() public {
        vm.prank(admin);
        burnerLoansConfig.setConfigurator(address(configTimelockHarness));

        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _riskAction(_termUpdate(14 days), _termSelection());
        actions[1] = _riskAction(_horizonUpdate(21 days), _horizonSelection());

        IBurnerLoans.AssetConfig memory liveConfig = burnerLoans.getAssetConfig(address(usds));
        IBurnerLoans.AssetConfig memory projectedAfterTerm = IBurnerLoans.AssetConfig({
            enabled: liveConfig.enabled,
            collateralDecimals: liveConfig.collateralDecimals,
            collateralFactorBps: liveConfig.collateralFactorBps,
            minCollateralRatioBps: liveConfig.minCollateralRatioBps,
            backingMultiplierBps: liveConfig.backingMultiplierBps,
            keeperRewardBps: liveConfig.keeperRewardBps,
            termLength: 14 days,
            maxMaturityHorizon: liveConfig.maxMaturityHorizon,
            debtCap: liveConfig.debtCap,
            maxKeeperReward: liveConfig.maxKeeperReward
        });
        IBurnerLoans.AssetConfig memory projectedAfterHorizon = IBurnerLoans.AssetConfig({
            enabled: liveConfig.enabled,
            collateralDecimals: liveConfig.collateralDecimals,
            collateralFactorBps: liveConfig.collateralFactorBps,
            minCollateralRatioBps: liveConfig.minCollateralRatioBps,
            backingMultiplierBps: liveConfig.backingMultiplierBps,
            keeperRewardBps: liveConfig.keeperRewardBps,
            termLength: 14 days,
            maxMaturityHorizon: 21 days,
            debtCap: liveConfig.debtCap,
            maxKeeperReward: liveConfig.maxKeeperReward
        });

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelockHarness.queueBatch(actions);

        assertEq(
            configTimelockHarness.expectedPreStateHash(actionId, 0),
            keccak256(abi.encode(address(usds), liveConfig)),
            "first pre-state"
        );
        assertEq(
            configTimelockHarness.expectedPreStateHash(actionId, 1),
            keccak256(abi.encode(address(usds), projectedAfterTerm)),
            "second pre-state"
        );

        (
            bool exists,
            address asset,
            IBurnerLoans.AssetConfig memory storedConfig
        ) = configTimelockHarness.assetConfigPostState(actionId, 0);
        assertTrue(exists, "first post-state stored");
        assertEq(asset, address(usds), "first post-state asset");
        assertEq(
            keccak256(abi.encode(storedConfig)),
            keccak256(abi.encode(projectedAfterTerm)),
            "first post-state"
        );

        (exists, asset, storedConfig) = configTimelockHarness.assetConfigPostState(actionId, 1);
        assertTrue(exists, "second post-state stored");
        assertEq(asset, address(usds), "second post-state asset");
        assertEq(
            keccak256(abi.encode(storedConfig)),
            keccak256(abi.encode(projectedAfterHorizon)),
            "second post-state"
        );

        vm.warp(block.timestamp + configTimelockHarness.timelockDelay());
        configTimelockHarness.executeQueuedAction(actionId);

        IBurnerLoans.AssetConfig memory finalConfig = burnerLoans.getAssetConfig(address(usds));
        assertEq(finalConfig.termLength, 14 days, "final term length");
        assertEq(finalConfig.maxMaturityHorizon, 21 days, "final max maturity horizon");
    }

    // executeQueuedAction
    // given a queued batch has two fee sub-actions for the same asset
    //  when the batch is queued
    //   then pre-state and post-state are captured against each intermediate fee config
    function test_givenSameAssetFeeBatch_capturesIntermediatePreAndPostState() public {
        vm.prank(admin);
        burnerLoansConfig.setConfigurator(address(configTimelockHarness));

        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _feeAction(_baseFeeUpdate(50), _baseFeeSelection());
        actions[1] = _feeAction(_preKinkSlopeUpdate(200), _preKinkSlopeSelection());

        IBurnerLoans.AssetFeeConfig memory liveConfig = burnerLoans.getAssetFeeConfig(
            address(usds)
        );
        IBurnerLoans.AssetFeeConfig memory projectedAfterBaseFee = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 50,
            kinkBps: liveConfig.kinkBps,
            preKinkSlopeBps: liveConfig.preKinkSlopeBps,
            postKinkSlopeBps: liveConfig.postKinkSlopeBps
        });
        IBurnerLoans.AssetFeeConfig memory projectedAfterSlope = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 50,
            kinkBps: liveConfig.kinkBps,
            preKinkSlopeBps: 200,
            postKinkSlopeBps: liveConfig.postKinkSlopeBps
        });

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelockHarness.queueBatch(actions);

        assertEq(
            configTimelockHarness.expectedPreStateHash(actionId, 0),
            keccak256(abi.encode(address(usds), liveConfig)),
            "first pre-state"
        );
        assertEq(
            configTimelockHarness.expectedPreStateHash(actionId, 1),
            keccak256(abi.encode(address(usds), projectedAfterBaseFee)),
            "second pre-state"
        );

        (
            bool exists,
            address asset,
            IBurnerLoans.AssetFeeConfig memory storedConfig
        ) = configTimelockHarness.feeConfigPostState(actionId, 0);
        assertTrue(exists, "first post-state stored");
        assertEq(asset, address(usds), "first post-state asset");
        assertEq(
            keccak256(abi.encode(storedConfig)),
            keccak256(abi.encode(projectedAfterBaseFee)),
            "first post-state"
        );

        (exists, asset, storedConfig) = configTimelockHarness.feeConfigPostState(actionId, 1);
        assertTrue(exists, "second post-state stored");
        assertEq(asset, address(usds), "second post-state asset");
        assertEq(
            keccak256(abi.encode(storedConfig)),
            keccak256(abi.encode(projectedAfterSlope)),
            "second post-state"
        );

        vm.warp(block.timestamp + configTimelockHarness.timelockDelay());
        configTimelockHarness.executeQueuedAction(actionId);

        IBurnerLoans.AssetFeeConfig memory finalConfig = burnerLoans.getAssetFeeConfig(
            address(usds)
        );
        assertEq(finalConfig.baseFeeBps, 50, "final base fee");
        assertEq(finalConfig.preKinkSlopeBps, 200, "final pre-kink slope");
    }

    // executeQueuedAction
    // given a queued batch has two dependent risk sub-actions
    //  when the batch executes after the delay
    //   then sub-actions execute atomically in array order
    function test_givenDelayElapsed_executesBatchInOrder() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _riskAction(_termUpdate(14 days), _termSelection());
        actions[1] = _riskAction(_horizonUpdate(21 days), _horizonSelection());

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueBatch(actions);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        configTimelock.executeQueuedAction(actionId);

        IBurnerLoans.AssetConfig memory config = burnerLoans.getAssetConfig(address(usds));
        assertEq(config.termLength, 14 days, "term length");
        assertEq(config.maxMaturityHorizon, 21 days, "max maturity horizon");
    }

    // executeQueuedAction
    // given a queued batch where the second sub-action pre-state becomes stale
    //  when execution reaches the stale sub-action
    //   then the whole batch reverts and the first sub-action is rolled back
    function test_givenLaterSubActionStale_revertsAtomically() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _riskAction(_collateralFactorUpdate(9_500), _collateralFactorSelection());
        actions[1] = _feeAction(_baseFeeUpdate(30), _baseFeeSelection());

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueBatch(actions);

        IBurnerLoans.AssetFeeConfig memory staleFeeConfig = _defaultAssetFeeConfig();
        staleFeeConfig.baseFeeBps = 40;
        vm.prank(admin);
        burnerLoans.setAssetFeeConfig(address(usds), staleFeeConfig);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ConfigStateChanged.selector,
                actionId,
                uint256(1),
                keccak256(abi.encode(address(usds), _defaultAssetFeeConfig())),
                keccak256(abi.encode(address(usds), staleFeeConfig))
            )
        );
        configTimelock.executeQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId);
        assertFalse(action.executed, "action not executed");
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            10_000,
            "first sub-action rolled back"
        );
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

    function _collateralFactorUpdate(
        uint16 collateralFactorBps_
    ) internal pure returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update) {
        update.collateralFactorBps = collateralFactorBps_;
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

    function _baseFeeUpdate(
        uint16 baseFeeBps_
    ) internal pure returns (IBurnerLoans.AssetFeeConfig memory update) {
        update.baseFeeBps = baseFeeBps_;
    }

    function _preKinkSlopeUpdate(
        uint16 preKinkSlopeBps_
    ) internal pure returns (IBurnerLoans.AssetFeeConfig memory update) {
        update.preKinkSlopeBps = preKinkSlopeBps_;
    }

    function _collateralFactorSelection()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection)
    {
        selection.collateralFactorBps = true;
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

    function _baseFeeSelection()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection)
    {
        selection.baseFeeBps = true;
    }

    function _preKinkSlopeSelection()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection)
    {
        selection.preKinkSlopeBps = true;
    }
}
