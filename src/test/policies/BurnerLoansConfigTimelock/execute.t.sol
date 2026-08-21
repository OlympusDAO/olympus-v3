// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {BurnerLoansConfigTimelockConfigGuardsTest} from "./BurnerLoansConfigTimelockConfigGuardsTest.sol";

contract BurnerLoansConfigTimelockExecuteTest is BurnerLoansConfigTimelockConfigGuardsTest {
    // executeQueuedAction
    // given a supported target setter reverts without error data
    //  when the queued action is executed
    //   then execution maps the empty revert to a descriptive custom error
    function test_givenTargetRevertsWithoutData_revertsWithSubActionError() public {
        uint128 debtCapOhm = 50_000e9;
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), debtCapOhm);
        vm.mockCallRevert(
            address(burnerLoansConfig),
            abi.encodeCall(IBurnerLoansConfig.setAssetDebtCap, (address(usds), debtCapOhm)),
            bytes("")
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_SubActionCallFailed.selector,
                address(burnerLoansConfig),
                IBurnerLoansConfig.setAssetDebtCap.selector
            )
        );
        configTimelock.executeQueuedAction(actionId);
    }

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
            burnerLoansConfig.getAssetConfig(address(usds)).collateralFactorBps,
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
            burnerLoansConfig.getAssetConfig(address(usds)).collateralFactorBps,
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
    //  when the configured config operator has been rotated
    //   then execution reverts and the queued action is stale
    function test_givenConfigOperatorRotated_reverts() public {
        uint64 actionId = _queueCollateralFactorUpdate();

        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(burnerLoans));
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                address(configTimelock)
            )
        );
        configTimelock.executeQueuedAction(actionId);
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
        emit AssetRiskConfigSet(address(usds), _assetRiskConfigInputFromConfig(resultingConfig));
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
            burnerLoansConfig.getAssetConfig(address(usds)).collateralFactorBps,
            9_500,
            "collateral factor"
        );
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
            burnerLoansConfig.getAssetFeeConfig(address(usds)).baseFeeBps,
            25,
            "fee config unchanged"
        );
        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).collateralFactorBps,
            9_500,
            "risk action applied"
        );
    }

    function test_givenFeeAndRiskForSameAsset_executesTogetherWithIndependentKeys() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _feeAction(30);
        actions[1] = _riskAction(9_500);

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueBatch(actions);

        (bytes32 feeKey, ) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        (bytes32 riskKey, ) = configTimelock.getQueuedConfigState(actionId, 1, 0);
        assertNotEq(feeKey, riskKey, "independent domains");

        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(actionId);

        assertEq(burnerLoansConfig.getAssetFeeConfig(address(usds)).baseFeeBps, 30, "fee update");
        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).collateralFactorBps,
            9_500,
            "risk update"
        );
    }

    function test_givenDisjointRiskChange_queuedFeeActionExecutes() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            _feeUpdate(30),
            _feeSelection()
        );

        IBurnerLoans.AssetConfig memory current = burnerLoansConfig.getAssetConfig(address(usds));
        IBurnerLoans.AssetRiskConfigInput memory risk = _assetRiskConfigInputFromConfig(current);
        risk.collateralFactorBps = 9_500;
        vm.prank(address(configTimelock));
        burnerLoansConfig.setAssetRiskConfig(address(usds), risk);

        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(actionId);
        assertEq(burnerLoansConfig.getAssetFeeConfig(address(usds)).baseFeeBps, 30, "fee update");
    }

    function test_givenFeeConfigChangesAfterQueue_executionRevertsAndKeepsKey() public {
        uint64 actionId = _queueFeeUpdate(_feeUpdate(30), _feeSelection());
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);

        IBurnerLoans.AssetFeeConfig memory changedConfig = _defaultAssetFeeConfig();
        changedConfig.baseFeeBps = 35;
        vm.prank(admin);
        burnerLoansConfig.setAssetFeeConfig(address(usds), changedConfig);
        bytes32 currentHash = keccak256(
            abi.encode(burnerLoansConfig.facility(), address(usds), changedConfig)
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                uint256(0),
                key,
                expectedHash,
                currentHash
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(configTimelock.pendingActionId(key), actionId, "fee key remains held");
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "action remains pending");
        assertEq(
            burnerLoansConfig.getAssetFeeConfig(address(usds)).baseFeeBps,
            35,
            "direct change retained"
        );
    }

    function test_givenRiskConfigChangesAfterQueue_executionRevertsAndKeepsKey() public {
        uint64 actionId = _queueAssetRiskUpdate(_riskUpdate(9_500), _riskSelection());
        (bytes32 key, bytes32 expectedHash) = configTimelock.getQueuedConfigState(actionId, 0, 0);

        IBurnerLoans.AssetConfig memory current = burnerLoansConfig.getAssetConfig(address(usds));
        IBurnerLoans.AssetRiskConfigInput memory changedConfig = _assetRiskConfigInputFromConfig(
            current
        );
        changedConfig.minCollateralRatioBps = 12_000;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), changedConfig);
        bytes32 currentHash = keccak256(
            abi.encode(burnerLoansConfig.facility(), address(usds), changedConfig)
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                actionId,
                uint256(0),
                key,
                expectedHash,
                currentHash
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(configTimelock.pendingActionId(key), actionId, "risk key remains held");
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "action remains pending");
        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).minCollateralRatioBps,
            12_000,
            "direct change retained"
        );
    }

    function test_givenLaterRealSetterReverts_rollsBackEarlierSetterAndKeepsBatchKeys() public {
        // queuedDebtCapOhm = 50,000 OHM in the token's 9-decimal scale.
        uint128 queuedDebtCapOhm = 50_000e9;
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _feeAction(30);
        actions[1] = _singleAction(
            IBurnerLoansConfig.setAssetDebtCap.selector,
            abi.encode(address(usds), queuedDebtCapOhm)
        );

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueBatch(actions);
        (bytes32 feeKey, ) = configTimelock.getQueuedConfigState(actionId, 0, 0);
        (bytes32 debtCapKey, ) = configTimelock.getQueuedConfigState(actionId, 1, 0);
        // One 9-decimal base unit above the queued cap forces the real setter to revert.
        burnerLoans.setActiveDebtForTest(address(usds), queuedDebtCapOhm + 1);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            burnerLoansConfig.getAssetFeeConfig(address(usds)).baseFeeBps,
            _defaultAssetFeeConfig().baseFeeBps,
            "earlier fee setter rolled back"
        );
        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).debtCap,
            _defaultAssetDebtCap(),
            "debt cap unchanged"
        );
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "batch remains pending");
        assertEq(configTimelock.pendingActionId(feeKey), actionId, "fee key remains held");
        assertEq(configTimelock.pendingActionId(debtCapKey), actionId, "cap key remains held");
    }

    function test_givenFacilityRotation_executionRevertsAndKeepsLogicalKey() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            _feeUpdate(30),
            _feeSelection()
        );
        (bytes32 key, ) = configTimelock.getQueuedConfigState(actionId, 0, 0);

        vm.mockCall(
            address(burnerLoansConfig),
            abi.encodeCall(IBurnerLoansConfig.facility, ()),
            abi.encode(address(0xBEEF))
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(configTimelock.pendingActionId(key), actionId, "logical key remains held");
    }

    function test_givenDebtCapChangesAfterQueue_executionRevertsAndKeepsKey() public {
        // Both values are OHM amounts in the token's 9-decimal scale.
        uint128 queuedDebtCapOhm = 90_000e9;
        uint128 changedDebtCapOhm = 95_000e9;
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetDebtCap(address(usds), queuedDebtCapOhm);
        (bytes32 key, ) = configTimelock.getQueuedConfigState(actionId, 0, 0);

        vm.prank(address(configTimelock));
        burnerLoansConfig.setAssetDebtCap(address(usds), changedDebtCapOhm);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(configTimelock.pendingActionId(key), actionId, "debt-cap key remains held");
    }

    function test_givenOriginationsChangeAfterQueue_executionRevertsAndKeepsKey() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(
            IBurnerLoansConfig.setAssetOriginationsEnabled.selector,
            abi.encode(address(usds), false)
        );
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueBatch(actions);
        (bytes32 key, ) = configTimelock.getQueuedConfigState(actionId, 0, 0);

        vm.prank(address(configTimelock));
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(configTimelock.pendingActionId(key), actionId, "origination key remains held");
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
