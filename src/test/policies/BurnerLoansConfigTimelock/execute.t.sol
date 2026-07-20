// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockExecuteTest is BurnerLoansConfigTimelockTest {
    // executeQueuedAction
    // given a queued action
    //  when called at any timestamp before the timelock delay has elapsed
    //   then it reverts and does not apply the setter
    function test_givenBeforeDelay_reverts(uint48 elapsed_) public {
        uint64 actionId = _queueCollateralFactorUpdate();
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId);
        uint256 queuedAt = action.queuedAt;
        uint48 timelockDelay = configTimelock.timelockDelay();
        elapsed_ = uint48(bound(elapsed_, 0, timelockDelay - 1));
        vm.warp(queuedAt + elapsed_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                actionId,
                action.executableAt
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            10_000,
            "collateral factor unchanged"
        );
    }

    // executeQueuedAction
    // given a queued action
    //  when called at any timestamp after the execution window expires
    //   then it reverts and does not apply the setter
    function test_givenExpired_reverts(uint48 elapsed_) public {
        uint64 actionId = _queueCollateralFactorUpdate();
        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId);
        uint256 queuedAt = action.queuedAt;
        uint48 firstExpiredElapsed = configTimelock.timelockDelay() +
            configTimelock.EXECUTION_WINDOW() +
            1;
        elapsed_ = uint48(bound(elapsed_, firstExpiredElapsed, type(uint48).max));
        vm.warp(queuedAt + elapsed_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            10_000,
            "collateral factor unchanged"
        );
    }

    // executeQueuedAction
    // given a queued action
    //  when BurnerLoansConfig has been disabled
    //   then execution reverts
    function test_givenBurnerLoansConfigDisabled_reverts() public {
        uint64 actionId = _queueCollateralFactorUpdate();
        vm.prank(emergency);
        burnerLoansConfig.disable("");
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.executeQueuedAction(actionId);
    }

    // executeQueuedAction
    // given a queued action
    //  when the config timelock has been disabled
    //   then execution reverts
    function test_givenConfigTimelockDisabled_reverts() public {
        uint64 actionId = _queueCollateralFactorUpdate();
        vm.prank(emergency);
        configTimelock.disable("");
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.executeQueuedAction(actionId);
    }

    // executeQueuedAction
    // given a queued action
    //  when the target asset has been disabled
    //   then execution reverts with the asset-disabled error
    function test_givenAssetDisabled_reverts() public {
        uint64 actionId = _queueCollateralFactorUpdate();
        vm.prank(emergency);
        burnerLoans.disableAsset(address(usds));
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotEnabled.selector, address(usds))
        );
        configTimelock.executeQueuedAction(actionId);
    }

    // executeQueuedAction
    // given a queued action
    //  when the BurnerLoans configurator has been rotated
    //   then execution reverts and the queued action is stale
    function test_givenConfiguratorRotated_reverts() public {
        uint64 actionId = _queueCollateralFactorUpdate();

        vm.prank(admin);
        burnerLoansConfig.setConfigurator(makeAddr("newConfigurator"));
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnauthorizedConfigurator.selector,
                address(configTimelock)
            )
        );
        configTimelock.executeQueuedAction(actionId);
    }

    // executeQueuedAction
    // given a batch of queued actions
    //  when called at any timestamp before the timelock delay has elapsed
    //   then it reverts and does not apply any setter
    function test_givenBatchBeforeDelay_reverts(uint48 elapsed_) public {
        uint64 actionId = _queueBatch();
        ITimelockBatchQueue.QueuedAction memory action = configTimelockHarness.getQueuedAction(
            actionId
        );
        uint256 queuedAt = action.queuedAt;
        uint48 timelockDelay = configTimelockHarness.timelockDelay();
        elapsed_ = uint48(bound(elapsed_, 0, timelockDelay - 1));
        vm.warp(queuedAt + elapsed_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                actionId,
                action.executableAt
            )
        );
        configTimelockHarness.executeQueuedAction(actionId);

        IBurnerLoans.AssetConfig memory config = burnerLoans.getAssetConfig(address(usds));
        assertEq(config.collateralFactorBps, 10_000, "collateral factor unchanged");
        assertEq(config.minCollateralRatioBps, 11_500, "min collateral ratio unchanged");
    }

    // executeQueuedAction
    // given a batch of queued actions
    //  when called at any timestamp after the execution window expires
    //   then it reverts and does not apply any setter
    function test_givenBatchExpired_reverts(uint48 elapsed_) public {
        uint64 actionId = _queueBatch();
        ITimelockBatchQueue.QueuedAction memory action = configTimelockHarness.getQueuedAction(
            actionId
        );
        uint256 queuedAt = action.queuedAt;
        uint48 firstExpiredElapsed = configTimelockHarness.timelockDelay() +
            configTimelockHarness.EXECUTION_WINDOW() +
            1;
        elapsed_ = uint48(bound(elapsed_, firstExpiredElapsed, type(uint48).max));
        vm.warp(queuedAt + elapsed_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        configTimelockHarness.executeQueuedAction(actionId);

        IBurnerLoans.AssetConfig memory config = burnerLoans.getAssetConfig(address(usds));
        assertEq(config.collateralFactorBps, 10_000, "collateral factor unchanged");
        assertEq(config.minCollateralRatioBps, 11_500, "min collateral ratio unchanged");
    }

    // executeQueuedAction
    // given a valid queued action
    //  when called at any timestamp within the execution window
    //   then any caller can execute and the BurnerLoans setter is applied
    function test_givenDelayElapsed_executesAction(address executor_, uint48 elapsed_) public {
        uint64 actionId = _queueCollateralFactorUpdate();
        uint256 queuedAt = block.timestamp;
        uint48 timelockDelay = configTimelock.timelockDelay();
        elapsed_ = uint48(
            bound(elapsed_, timelockDelay, timelockDelay + configTimelock.EXECUTION_WINDOW())
        );
        vm.warp(queuedAt + elapsed_);
        IBurnerLoans.AssetConfig memory resultingConfig = _defaultAssetConfig(USDS_DECIMALS);
        resultingConfig.collateralFactorBps = 9_500;

        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetRiskConfigSet(address(usds), _toRiskConfig(resultingConfig));
        _expectSingleActionExecuted(
            actionId,
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            executor_
        );

        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId);
        assertTrue(action.executed, "executed");
        assertEq(action.actions.length, 0, "sub-actions cleared");
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            9_500,
            "collateral factor"
        );
    }

    // executeQueuedAction
    // given two queued actions update different fields on the same asset risk config
    //  when both actions execute
    //   then the second action preserves the first action's selected-field update
    function test_givenDifferentRiskFieldsQueuedSeparately_executesIncrementally() public {
        uint64 collateralFactorActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 9_500,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: true,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        uint64 minCollateralRatioActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 12_000,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: false,
                minCollateralRatioBps: true,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // The second action was queued against the projected config from the first action.
        // Executing in order should apply each selected field without overwriting the other.
        _expectSingleActionExecuted(
            collateralFactorActionId,
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            address(this)
        );
        configTimelock.executeQueuedAction(collateralFactorActionId);

        IBurnerLoans.AssetConfig memory config = burnerLoans.getAssetConfig(address(usds));
        assertEq(config.collateralFactorBps, 9_500, "collateral factor after first action");
        assertEq(config.minCollateralRatioBps, 11_500, "min collateral ratio after first action");

        // The later action should preserve the collateral factor that was already applied.
        _expectSingleActionExecuted(
            minCollateralRatioActionId,
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            address(this)
        );
        configTimelock.executeQueuedAction(minCollateralRatioActionId);

        config = burnerLoans.getAssetConfig(address(usds));
        assertEq(config.collateralFactorBps, 9_500, "collateral factor preserved");
        assertEq(config.minCollateralRatioBps, 12_000, "min collateral ratio applied");
    }

    // executeQueuedAction
    // given two queued actions update the same asset risk config field
    //  when both actions execute in order
    //   then the later executed action determines the final selected-field value
    function test_givenSameRiskFieldQueuedSeparately_laterExecutionWins() public {
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection
            memory selection = IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: true,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            });
        uint64 firstActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 9_500,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            selection
        );
        uint64 secondActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 9_000,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            selection
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // Both actions target the same field, so the first execution is valid but temporary.
        _expectSingleActionExecuted(
            firstActionId,
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            address(this)
        );
        configTimelock.executeQueuedAction(firstActionId);
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            9_500,
            "first value applied"
        );

        // The second execution is also valid because its expected pre-state includes the first
        // value, and it intentionally becomes the final value.
        _expectSingleActionExecuted(
            secondActionId,
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            address(this)
        );
        configTimelock.executeQueuedAction(secondActionId);
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            9_000,
            "second value applied"
        );
    }

    // executeQueuedAction
    // given the underlying config changes after an action is queued
    //  when the queued action executes
    //   then it reverts because the queue-time pre-state is stale
    function test_givenConfigChangedAfterQueue_reverts() public {
        uint64 actionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 9_500,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: true,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        // Simulate governance/admin changing the same config before the timelock action executes.
        // The queued action should not blindly apply over a state it was not validated against.
        IBurnerLoans.AssetConfig memory adminConfig = _defaultAssetConfig(USDS_DECIMALS);
        adminConfig.collateralFactorBps = 9_800;
        vm.prank(admin);
        burnerLoans.setAssetRiskConfig(address(usds), _toRiskConfig(adminConfig));
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            9_800,
            "admin value applied"
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // The expected hash is the queue-time config; the current hash includes the direct admin
        // update, so execution must revert as stale.
        IBurnerLoans.AssetConfig memory expectedConfig = _defaultAssetConfig(USDS_DECIMALS);
        IBurnerLoans.AssetConfig memory currentConfig = _defaultAssetConfig(USDS_DECIMALS);
        currentConfig.collateralFactorBps = 9_800;
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ConfigStateChanged.selector,
                actionId,
                uint256(0),
                keccak256(abi.encode(address(usds), expectedConfig)),
                keccak256(abi.encode(address(usds), currentConfig))
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            9_800,
            "admin value preserved"
        );
    }

    // executeQueuedAction
    // given two queued actions update the same asset risk config
    //  when the later action is executed before the earlier action
    //   then it reverts because the later action was validated against the projected earlier state
    function test_givenPriorQueuedRiskActionNotExecuted_revertsAsStale() public {
        uint64 collateralFactorActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 9_500,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: true,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        uint64 minCollateralRatioActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 12_000,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: false,
                minCollateralRatioBps: true,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // The min collateral ratio action was queued after a pending collateral-factor action,
        // so its expected pre-state includes collateralFactorBps = 9_500.
        IBurnerLoans.AssetConfig memory expectedConfig = _defaultAssetConfig(USDS_DECIMALS);
        expectedConfig.collateralFactorBps = 9_500;
        IBurnerLoans.AssetConfig memory currentConfig = _defaultAssetConfig(USDS_DECIMALS);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ConfigStateChanged.selector,
                minCollateralRatioActionId,
                uint256(0),
                keccak256(abi.encode(address(usds), expectedConfig)),
                keccak256(abi.encode(address(usds), currentConfig))
            )
        );
        configTimelock.executeQueuedAction(minCollateralRatioActionId);

        assertEq(collateralFactorActionId, 1, "first action id");
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            10_000,
            "collateral factor unchanged"
        );
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).minCollateralRatioBps,
            11_500,
            "min cr unchanged"
        );
    }

    // executeQueuedAction
    // given a later risk action was validated against an earlier queued risk action
    //  when executing the later action first and then in order
    //   then stale-state execution reverts and applying the earlier action first makes it executable
    function test_givenRiskActionDependsOnEarlierRiskAction_revertsUntilEarlierActionExecutes()
        public
    {
        uint64 termActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 14 days,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: false,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: true,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        uint64 horizonActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 21 days,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: false,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: true,
                maxKeeperReward: false
            })
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // The horizon action was queued against the projected 14-day term. Executing it
        // first should fail because the live config still has the default 30-day term.
        IBurnerLoans.AssetConfig memory expectedConfig = _defaultAssetConfig(USDS_DECIMALS);
        expectedConfig.termLength = 14 days;
        IBurnerLoans.AssetConfig memory currentConfig = _defaultAssetConfig(USDS_DECIMALS);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ConfigStateChanged.selector,
                horizonActionId,
                uint256(0),
                keccak256(abi.encode(address(usds), expectedConfig)),
                keccak256(abi.encode(address(usds), currentConfig))
            )
        );
        configTimelock.executeQueuedAction(horizonActionId);

        // Once the term update executes, the horizon update's expected pre-state exists.
        configTimelock.executeQueuedAction(termActionId);
        configTimelock.executeQueuedAction(horizonActionId);

        IBurnerLoans.AssetConfig memory config = burnerLoans.getAssetConfig(address(usds));
        assertEq(config.termLength, 14 days, "term length");
        assertEq(config.maxMaturityHorizon, 21 days, "max maturity horizon");
    }

    // executeQueuedAction
    // given a later termLength action was validated against an earlier maxMaturityHorizon action
    //  when executing the later action first and then in order
    //   then stale-state execution reverts and applying the earlier action first makes it executable
    function test_givenTermActionDependsOnEarlierHorizonAction_revertsUntilEarlierActionExecutes()
        public
    {
        uint64 horizonActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 120 days,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: false,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: true,
                maxKeeperReward: false
            })
        );
        uint64 termActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 100 days,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: false,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: true,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // The termLength update was queued against the projected state after the horizon
        // update. Executing it first must fail because the live asset config still has the
        // default horizon, so the queue-time pre-state hash does not match.
        IBurnerLoans.AssetConfig memory expectedConfig = _defaultAssetConfig(USDS_DECIMALS);
        expectedConfig.maxMaturityHorizon = 120 days;
        IBurnerLoans.AssetConfig memory currentConfig = _defaultAssetConfig(USDS_DECIMALS);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ConfigStateChanged.selector,
                termActionId,
                uint256(0),
                keccak256(abi.encode(address(usds), expectedConfig)),
                keccak256(abi.encode(address(usds), currentConfig))
            )
        );
        configTimelock.executeQueuedAction(termActionId);

        // Once the horizon action has executed, the live config matches the term action's
        // expected pre-state and the dependent termLength update can execute.
        configTimelock.executeQueuedAction(horizonActionId);
        configTimelock.executeQueuedAction(termActionId);

        IBurnerLoans.AssetConfig memory config = burnerLoans.getAssetConfig(address(usds));
        assertEq(config.termLength, 100 days, "term length");
        assertEq(config.maxMaturityHorizon, 120 days, "max maturity horizon");
    }

    // executeQueuedAction
    // given a later fee action was validated against an earlier queued fee action
    //  when executing the later action first and then in order
    //   then stale-state execution reverts and applying the earlier action first makes it executable
    function test_givenFeeActionDependsOnEarlierFeeAction_revertsUntilEarlierActionExecutes()
        public
    {
        uint64 singleSlopeActionId = _queueFeeUpdate(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 0,
                kinkBps: 0,
                preKinkSlopeBps: 0,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: true,
                kinkBps: true,
                preKinkSlopeBps: false,
                postKinkSlopeBps: true
            })
        );
        uint64 slopeActionId = _queueFeeUpdate(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 0,
                kinkBps: 0,
                preKinkSlopeBps: 10_000,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: false,
                kinkBps: false,
                preKinkSlopeBps: true,
                postKinkSlopeBps: false
            })
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // The slope action was queued against the projected single-slope fee config.
        // Executing it first should fail because the live config is still kinked.
        IBurnerLoans.AssetFeeConfig memory expectedConfig = _defaultAssetFeeConfig();
        expectedConfig.baseFeeBps = 0;
        expectedConfig.kinkBps = 0;
        expectedConfig.postKinkSlopeBps = 0;
        IBurnerLoans.AssetFeeConfig memory currentConfig = _defaultAssetFeeConfig();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ConfigStateChanged.selector,
                slopeActionId,
                uint256(0),
                keccak256(abi.encode(address(usds), expectedConfig)),
                keccak256(abi.encode(address(usds), currentConfig))
            )
        );
        configTimelock.executeQueuedAction(slopeActionId);

        // Once the domain-changing action executes, the slope action's expected pre-state
        // exists and the max single-slope update can execute.
        configTimelock.executeQueuedAction(singleSlopeActionId);
        configTimelock.executeQueuedAction(slopeActionId);

        IBurnerLoans.AssetFeeConfig memory config = burnerLoans.getAssetFeeConfig(address(usds));
        assertEq(config.baseFeeBps, 0, "base fee");
        assertEq(config.kinkBps, 0, "kink");
        assertEq(config.preKinkSlopeBps, 10_000, "preKinkSlope");
        assertEq(config.postKinkSlopeBps, 0, "postKinkSlope");
    }

    // executeQueuedAction
    // given a risk action is queued after an unrelated fee action
    //  when the fee action is cancelled before execution
    //   then the risk action still executes because its pre-state does not depend on fee config
    function test_givenRiskActionAfterFeeAction_whenFeeActionCancelled_executesRiskAction() public {
        uint64 feeActionId = _queueFeeUpdate(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 30,
                kinkBps: 0,
                preKinkSlopeBps: 0,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: true,
                kinkBps: false,
                preKinkSlopeBps: false,
                postKinkSlopeBps: false
            })
        );
        uint64 riskActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 9_500,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: true,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );

        // Cancel the fee action to prove unrelated cancelled actions do not block a later risk
        // action that was validated against the live asset-risk state.
        vm.prank(emergency);
        configTimelock.cancelQueuedAction(feeActionId);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // The risk action can execute even though an earlier fee action was cancelled.
        configTimelock.executeQueuedAction(riskActionId);

        assertEq(
            burnerLoans.getAssetFeeConfig(address(usds)).baseFeeBps,
            25,
            "fee config unchanged"
        );
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            9_500,
            "risk action applied"
        );
    }

    // executeQueuedAction
    // given a fee action is queued between two dependent risk actions
    //  when executing out of order and then in order
    //   then the later risk action depends only on the earlier risk action, not the fee action
    function test_givenFeeActionBetweenRiskActions_laterRiskActionIgnoresUnrelatedFeeAction()
        public
    {
        uint64 termActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 14 days,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: false,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: true,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        uint64 feeActionId = _queueFeeUpdate(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 30,
                kinkBps: 0,
                preKinkSlopeBps: 0,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: true,
                kinkBps: false,
                preKinkSlopeBps: false,
                postKinkSlopeBps: false
            })
        );
        uint64 horizonActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 21 days,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: false,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: true,
                maxKeeperReward: false
            })
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // The horizon action depends on the pending term action, not on the unrelated fee
        // action. It should fail before the term action executes because the risk pre-state
        // is stale.
        IBurnerLoans.AssetConfig memory expectedConfig = _defaultAssetConfig(USDS_DECIMALS);
        expectedConfig.termLength = 14 days;
        IBurnerLoans.AssetConfig memory currentConfig = _defaultAssetConfig(USDS_DECIMALS);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ConfigStateChanged.selector,
                horizonActionId,
                uint256(0),
                keccak256(abi.encode(address(usds), expectedConfig)),
                keccak256(abi.encode(address(usds), currentConfig))
            )
        );
        configTimelock.executeQueuedAction(horizonActionId);

        // The fee action remains queued, but it is unrelated to asset-risk state. The later
        // risk action can execute as soon as its risk dependency has executed.
        configTimelock.executeQueuedAction(termActionId);
        configTimelock.executeQueuedAction(horizonActionId);
        configTimelock.executeQueuedAction(feeActionId);

        IBurnerLoans.AssetConfig memory assetConfig = burnerLoans.getAssetConfig(address(usds));
        assertEq(assetConfig.termLength, 14 days, "term length");
        assertEq(assetConfig.maxMaturityHorizon, 21 days, "max maturity horizon");
        assertEq(burnerLoans.getAssetFeeConfig(address(usds)).baseFeeBps, 30, "fee action applied");
    }

    // executeQueuedAction
    // given a fee action between two dependent risk actions is cancelled
    //  when executing the risk actions in order
    //   then the later risk action still executes because it does not depend on fee config
    function test_givenFeeActionBetweenRiskActions_whenFeeActionCancelled_executesLaterRiskAction()
        public
    {
        uint64 termActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 14 days,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: false,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: true,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        uint64 feeActionId = _queueFeeUpdate(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 30,
                kinkBps: 0,
                preKinkSlopeBps: 0,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: true,
                kinkBps: false,
                preKinkSlopeBps: false,
                postKinkSlopeBps: false
            })
        );
        uint64 horizonActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 21 days,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: false,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: true,
                maxKeeperReward: false
            })
        );

        // Cancel the middle fee action. The later risk action should still depend only on the
        // earlier risk action, so cancelling the unrelated fee action must not stale it.
        vm.prank(emergency);
        configTimelock.cancelQueuedAction(feeActionId);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // Applying the term action creates the expected pre-state for the horizon action.
        configTimelock.executeQueuedAction(termActionId);
        configTimelock.executeQueuedAction(horizonActionId);

        IBurnerLoans.AssetConfig memory assetConfig = burnerLoans.getAssetConfig(address(usds));
        assertEq(assetConfig.termLength, 14 days, "term length");
        assertEq(assetConfig.maxMaturityHorizon, 21 days, "max maturity horizon");
        assertEq(
            burnerLoans.getAssetFeeConfig(address(usds)).baseFeeBps,
            25,
            "fee config unchanged"
        );
    }

    // executeQueuedAction
    // given a risk action is queued between two dependent fee actions
    //  when executing out of order and then in order
    //   then the later fee action depends only on the earlier fee action, not the risk action
    function test_givenRiskActionBetweenFeeActions_laterFeeActionIgnoresUnrelatedRiskAction()
        public
    {
        uint64 singleSlopeActionId = _queueFeeUpdate(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 0,
                kinkBps: 0,
                preKinkSlopeBps: 0,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: true,
                kinkBps: true,
                preKinkSlopeBps: false,
                postKinkSlopeBps: true
            })
        );
        uint64 riskActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 9_500,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: true,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        uint64 slopeActionId = _queueFeeUpdate(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 0,
                kinkBps: 0,
                preKinkSlopeBps: 10_000,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: false,
                kinkBps: false,
                preKinkSlopeBps: true,
                postKinkSlopeBps: false
            })
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // The slope action depends on the pending fee-domain action, not on the unrelated
        // risk action. It should fail before the single-slope action executes because the
        // fee pre-state is stale.
        IBurnerLoans.AssetFeeConfig memory expectedConfig = _defaultAssetFeeConfig();
        expectedConfig.baseFeeBps = 0;
        expectedConfig.kinkBps = 0;
        expectedConfig.postKinkSlopeBps = 0;
        IBurnerLoans.AssetFeeConfig memory currentConfig = _defaultAssetFeeConfig();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ConfigStateChanged.selector,
                slopeActionId,
                uint256(0),
                keccak256(abi.encode(address(usds), expectedConfig)),
                keccak256(abi.encode(address(usds), currentConfig))
            )
        );
        configTimelock.executeQueuedAction(slopeActionId);

        // The risk action remains queued, but it is unrelated to fee state. The later fee
        // action can execute as soon as its fee dependency has executed.
        configTimelock.executeQueuedAction(singleSlopeActionId);
        configTimelock.executeQueuedAction(slopeActionId);
        configTimelock.executeQueuedAction(riskActionId);

        IBurnerLoans.AssetFeeConfig memory feeConfig = burnerLoans.getAssetFeeConfig(address(usds));
        assertEq(feeConfig.kinkBps, 0, "kink");
        assertEq(feeConfig.preKinkSlopeBps, 10_000, "preKinkSlope");
        assertEq(feeConfig.postKinkSlopeBps, 0, "postKinkSlope");
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            9_500,
            "risk action applied"
        );
    }

    // executeQueuedAction
    // given a risk action between two dependent fee actions is cancelled
    //  when executing the fee actions in order
    //   then the later fee action still executes because it does not depend on risk config
    function test_givenRiskActionBetweenFeeActions_whenRiskActionCancelled_executesLaterFeeAction()
        public
    {
        uint64 singleSlopeActionId = _queueFeeUpdate(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 0,
                kinkBps: 0,
                preKinkSlopeBps: 0,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: true,
                kinkBps: true,
                preKinkSlopeBps: false,
                postKinkSlopeBps: true
            })
        );
        uint64 riskActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 9_500,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: true,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        uint64 slopeActionId = _queueFeeUpdate(
            IBurnerLoans.AssetFeeConfig({
                baseFeeBps: 0,
                kinkBps: 0,
                preKinkSlopeBps: 10_000,
                postKinkSlopeBps: 0
            }),
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
                baseFeeBps: false,
                kinkBps: false,
                preKinkSlopeBps: true,
                postKinkSlopeBps: false
            })
        );

        // Cancel the unrelated middle risk action. The later fee action should still be executable
        // once the earlier fee action applies the fee-domain pre-state it depends on.
        vm.prank(emergency);
        configTimelock.cancelQueuedAction(riskActionId);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // The cancelled risk action is ignored by fee-domain dependency checks.
        configTimelock.executeQueuedAction(singleSlopeActionId);
        configTimelock.executeQueuedAction(slopeActionId);

        IBurnerLoans.AssetFeeConfig memory feeConfig = burnerLoans.getAssetFeeConfig(address(usds));
        assertEq(feeConfig.kinkBps, 0, "kink");
        assertEq(feeConfig.preKinkSlopeBps, 10_000, "preKinkSlope");
        assertEq(feeConfig.postKinkSlopeBps, 0, "postKinkSlope");
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            10_000,
            "risk config unchanged"
        );
    }

    // executeQueuedAction
    // given a prior queued action is cancelled after a later action was validated against it
    //  when the later action executes
    //   then it reverts because the projected pre-state was never applied
    function test_givenPriorQueuedActionCancelled_revertsAsStale() public {
        uint64 collateralFactorActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 9_500,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: true,
                minCollateralRatioBps: false,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );
        uint64 minCollateralRatioActionId = _queueAssetRiskUpdate(
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 12_000,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
                collateralFactorBps: false,
                minCollateralRatioBps: true,
                backingMultiplierBps: false,
                keeperRewardBps: false,
                termLength: false,
                maxMaturityHorizon: false,
                maxKeeperReward: false
            })
        );

        // The second action was queued against the projected state from the first action.
        // Cancelling the first action means that projected state will never exist.
        vm.prank(emergency);
        configTimelock.cancelQueuedAction(collateralFactorActionId);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // The later action should fail stale rather than applying over the unchanged live config.
        IBurnerLoans.AssetConfig memory expectedConfig = _defaultAssetConfig(USDS_DECIMALS);
        expectedConfig.collateralFactorBps = 9_500;
        IBurnerLoans.AssetConfig memory currentConfig = _defaultAssetConfig(USDS_DECIMALS);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ConfigStateChanged.selector,
                minCollateralRatioActionId,
                uint256(0),
                keccak256(abi.encode(address(usds), expectedConfig)),
                keccak256(abi.encode(address(usds), currentConfig))
            )
        );
        configTimelock.executeQueuedAction(minCollateralRatioActionId);

        assertEq(collateralFactorActionId, 1, "first action id");
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).collateralFactorBps,
            10_000,
            "collateral factor unchanged"
        );
        assertEq(
            burnerLoans.getAssetConfig(address(usds)).minCollateralRatioBps,
            11_500,
            "min cr unchanged"
        );
    }

    // executeQueuedAction
    // given a batch of valid actions
    //  when called at any timestamp within the execution window and the harness is the configurator
    //   then all sub-actions execute atomically in order
    function test_givenBatch_executesAllSubActions(address executor_, uint48 elapsed_) public {
        uint64 actionId = _queueBatch();
        uint256 queuedAt = block.timestamp;
        uint48 timelockDelay = configTimelockHarness.timelockDelay();
        elapsed_ = uint48(
            bound(elapsed_, timelockDelay, timelockDelay + configTimelockHarness.EXECUTION_WINDOW())
        );
        vm.warp(queuedAt + elapsed_);

        // The batch is expected to emit and apply sub-actions sequentially. The second expected
        // resulting config includes the first sub-action's collateral factor update.
        IBurnerLoans.AssetConfig memory resultingConfigOne = _defaultAssetConfig(USDS_DECIMALS);
        resultingConfigOne.collateralFactorBps = 9_500;
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetRiskConfigSet(address(usds), _toRiskConfig(resultingConfigOne));
        vm.expectEmit(true, true, true, true, address(configTimelockHarness));
        emit TimelockSubActionExecuted(
            actionId,
            address(burnerLoansConfig),
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            0
        );
        IBurnerLoans.AssetConfig memory resultingConfigTwo = resultingConfigOne;
        resultingConfigTwo.minCollateralRatioBps = 12_000;
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetRiskConfigSet(address(usds), _toRiskConfig(resultingConfigTwo));
        vm.expectEmit(true, true, true, true, address(configTimelockHarness));
        emit TimelockSubActionExecuted(
            actionId,
            address(burnerLoansConfig),
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            1
        );
        vm.expectEmit(true, true, false, true, address(configTimelockHarness));
        emit TimelockActionExecuted(actionId, executor_);
        vm.prank(executor_);
        configTimelockHarness.executeQueuedAction(actionId);

        IBurnerLoans.AssetConfig memory config = burnerLoans.getAssetConfig(address(usds));
        assertEq(config.collateralFactorBps, 9_500, "collateral factor");
        assertEq(config.minCollateralRatioBps, 12_000, "min collateral ratio");
    }

    // executeQueuedAction
    // given a queued risk batch has expected pre-state and projected post-state
    //  when the batch executes
    //   then stale pre-state and risk post-state storage is cleared for every sub-action
    function test_givenRiskBatch_clearsStoredStateOnExecution() public {
        uint64 actionId = _queueBatch();

        for (uint256 i; i < 2; ++i) {
            assertNotEq(
                configTimelockHarness.expectedPreStateHash(actionId, i),
                bytes32(0),
                "pre-state stored"
            );
            (bool exists, address asset, ) = configTimelockHarness.assetConfigPostState(
                actionId,
                i
            );
            assertTrue(exists, "asset post-state stored");
            assertEq(asset, address(usds), "asset");
        }

        vm.warp(block.timestamp + configTimelockHarness.timelockDelay());
        configTimelockHarness.executeQueuedAction(actionId);

        for (uint256 i; i < 2; ++i) {
            assertEq(
                configTimelockHarness.expectedPreStateHash(actionId, i),
                bytes32(0),
                "pre-state cleared"
            );
            (
                bool exists,
                address asset,
                IBurnerLoans.AssetConfig memory config
            ) = configTimelockHarness.assetConfigPostState(actionId, i);
            assertFalse(exists, "asset post-state cleared");
            assertEq(asset, address(0), "asset cleared");
            assertEq(config.collateralFactorBps, 0, "post-state config cleared");
        }
    }

    // executeQueuedAction
    // given a batch where a later risk sub-action depends on an earlier risk sub-action
    //  when the batch executes
    //   then sub-action pre-state hashes are checked against the batch-local intermediate state
    function test_givenDependentRiskBatch_executesAgainstIntermediatePreState(
        address executor_,
        uint48 elapsed_
    ) public {
        uint64 actionId = _queueDependentRiskBatch();
        uint256 queuedAt = block.timestamp;
        uint48 timelockDelay = configTimelockHarness.timelockDelay();
        elapsed_ = uint48(
            bound(elapsed_, timelockDelay, timelockDelay + configTimelockHarness.EXECUTION_WINDOW())
        );
        vm.warp(queuedAt + elapsed_);

        vm.prank(executor_);
        configTimelockHarness.executeQueuedAction(actionId);

        IBurnerLoans.AssetConfig memory config = burnerLoans.getAssetConfig(address(usds));
        assertEq(config.termLength, 14 days, "term length");
        assertEq(config.maxMaturityHorizon, 21 days, "max maturity horizon");
    }

    // executeQueuedAction
    // given a batch where a later fee sub-action depends on an earlier fee sub-action
    //  when the batch executes
    //   then sub-action pre-state hashes are checked against the batch-local intermediate state
    function test_givenDependentFeeBatch_executesAgainstIntermediatePreState(
        address executor_,
        uint48 elapsed_
    ) public {
        uint64 actionId = _queueDependentFeeBatch();
        uint256 queuedAt = block.timestamp;
        uint48 timelockDelay = configTimelockHarness.timelockDelay();
        elapsed_ = uint48(
            bound(elapsed_, timelockDelay, timelockDelay + configTimelockHarness.EXECUTION_WINDOW())
        );
        vm.warp(queuedAt + elapsed_);

        vm.prank(executor_);
        configTimelockHarness.executeQueuedAction(actionId);

        IBurnerLoans.AssetFeeConfig memory config = burnerLoans.getAssetFeeConfig(address(usds));
        assertEq(config.baseFeeBps, 0, "base fee");
        assertEq(config.kinkBps, 0, "kink");
        assertEq(config.preKinkSlopeBps, 10_000, "preKinkSlope");
        assertEq(config.postKinkSlopeBps, 0, "postKinkSlope");
    }

    // executeQueuedAction
    // given a queued fee batch has expected pre-state and projected post-state
    //  when the batch executes
    //   then stale pre-state and fee post-state storage is cleared for every sub-action
    function test_givenFeeBatch_clearsStoredStateOnExecution() public {
        uint64 actionId = _queueDependentFeeBatch();

        for (uint256 i; i < 2; ++i) {
            assertNotEq(
                configTimelockHarness.expectedPreStateHash(actionId, i),
                bytes32(0),
                "pre-state stored"
            );
            (bool exists, address asset, ) = configTimelockHarness.feeConfigPostState(actionId, i);
            assertTrue(exists, "fee post-state stored");
            assertEq(asset, address(usds), "asset");
        }

        vm.warp(block.timestamp + configTimelockHarness.timelockDelay());
        configTimelockHarness.executeQueuedAction(actionId);

        for (uint256 i; i < 2; ++i) {
            assertEq(
                configTimelockHarness.expectedPreStateHash(actionId, i),
                bytes32(0),
                "pre-state cleared"
            );
            (
                bool exists,
                address asset,
                IBurnerLoans.AssetFeeConfig memory config
            ) = configTimelockHarness.feeConfigPostState(actionId, i);
            assertFalse(exists, "fee post-state cleared");
            assertEq(asset, address(0), "asset cleared");
            assertEq(config.preKinkSlopeBps, 0, "post-state config cleared");
        }
    }

    function _queueBatch() internal returns (uint64 actionId) {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate
            memory updateOne = IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 9_500,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            });
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate
            memory updateTwo = IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 12_000,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            });
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selectionOne;
        selectionOne.collateralFactorBps = true;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selectionTwo;
        selectionTwo.minCollateralRatioBps = true;
        actions[0] = _singleAction(
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            abi.encode(address(usds), updateOne, selectionOne)
        );
        actions[1] = _singleAction(
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            abi.encode(address(usds), updateTwo, selectionTwo)
        );

        vm.prank(admin);
        burnerLoansConfig.setConfigurator(address(configTimelockHarness));

        vm.prank(burnerLoansAdmin);
        actionId = configTimelockHarness.queueBatch(actions);
    }

    function _queueDependentRiskBatch() internal returns (uint64 actionId) {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory updateOne;
        updateOne.termLength = 14 days;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selectionOne;
        selectionOne.termLength = true;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory updateTwo;
        updateTwo.maxMaturityHorizon = 21 days;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selectionTwo;
        selectionTwo.maxMaturityHorizon = true;

        actions[0] = _singleAction(
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            abi.encode(address(usds), updateOne, selectionOne)
        );
        actions[1] = _singleAction(
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            abi.encode(address(usds), updateTwo, selectionTwo)
        );

        vm.prank(admin);
        burnerLoansConfig.setConfigurator(address(configTimelockHarness));

        vm.prank(burnerLoansAdmin);
        actionId = configTimelockHarness.queueBatch(actions);
    }

    function _queueDependentFeeBatch() internal returns (uint64 actionId) {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        IBurnerLoans.AssetFeeConfig memory updateOne = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 0,
            postKinkSlopeBps: 0
        });
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selectionOne;
        selectionOne.baseFeeBps = true;
        selectionOne.kinkBps = true;
        selectionOne.postKinkSlopeBps = true;
        IBurnerLoans.AssetFeeConfig memory updateTwo;
        updateTwo.preKinkSlopeBps = 10_000;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selectionTwo;
        selectionTwo.preKinkSlopeBps = true;

        actions[0] = _singleAction(
            IBurnerLoansConfig.setAssetFeeConfig.selector,
            abi.encode(address(usds), updateOne, selectionOne)
        );
        actions[1] = _singleAction(
            IBurnerLoansConfig.setAssetFeeConfig.selector,
            abi.encode(address(usds), updateTwo, selectionTwo)
        );

        vm.prank(admin);
        burnerLoansConfig.setConfigurator(address(configTimelockHarness));

        vm.prank(burnerLoansAdmin);
        actionId = configTimelockHarness.queueBatch(actions);
    }

    function _queueAssetRiskUpdate(
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update_,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection_
    ) internal returns (uint64 actionId) {
        vm.prank(burnerLoansAdmin);
        actionId = configTimelock.queueSetAssetRiskConfig(address(usds), update_, selection_);
    }

    function _queueFeeUpdate(
        IBurnerLoans.AssetFeeConfig memory update_,
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection_
    ) internal returns (uint64 actionId) {
        vm.prank(burnerLoansAdmin);
        actionId = configTimelock.queueSetAssetFeeConfig(address(usds), update_, selection_);
    }
}
