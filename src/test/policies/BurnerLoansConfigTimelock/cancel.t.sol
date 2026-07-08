// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockCancelTest is BurnerLoansConfigTimelockTest {
    // cancelQueuedAction
    // given caller does not have emergency role
    //  when cancelling a queued action
    //   then it reverts
    function test_givenNonEmergencyCaller_reverts(address caller_) public {
        vm.assume(caller_ != emergency);
        uint64 actionId = _queueCollateralFactorUpdate();

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        configTimelock.cancelQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given action has already been cancelled
    //  when executing at any later timestamp
    //   then execution reverts as cancelled
    function test_givenCancelledAction_reverts(uint48 elapsed_) public {
        uint64 actionId = _queueCollateralFactorUpdate();
        uint256 queuedAt = block.timestamp;
        elapsed_ = uint48(bound(elapsed_, 0, type(uint48).max));

        vm.prank(emergency);
        configTimelock.cancelQueuedAction(actionId);
        vm.warp(queuedAt + elapsed_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        configTimelock.executeQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given action has already been executed
    //  when emergency tries to cancel it after execution at any valid timestamp
    //   then it reverts
    function test_givenExecutedAction_reverts(uint48 elapsed_) public {
        uint64 actionId = _queueCollateralFactorUpdate();
        uint256 queuedAt = block.timestamp;
        uint48 timelockDelay = configTimelock.timelockDelay();
        elapsed_ = uint48(
            bound(elapsed_, timelockDelay, timelockDelay + configTimelock.EXECUTION_WINDOW())
        );
        vm.warp(queuedAt + elapsed_);
        configTimelock.executeQueuedAction(actionId);

        vm.prank(emergency);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        configTimelock.cancelQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given action id has never been queued
    //  when emergency tries to cancel it
    //   then it reverts
    function test_givenActionNotFound_reverts() public {
        uint64 actionId = configTimelock.nextActionId();

        vm.prank(emergency);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                actionId
            )
        );
        configTimelock.cancelQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given action has been cancelled
    //  when querying the accessible sub-action list
    //   then it reverts as cancelled
    function test_givenCancelledAction_cannotReadLength() public {
        uint64 actionId = _queueCollateralFactorUpdate();

        vm.prank(emergency);
        configTimelock.cancelQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        configTimelock.getQueuedActionLength(actionId);
    }

    // cancelQueuedAction
    // given a queued action
    //  when the timelock policy is disabled
    //   then emergency can still cancel it
    function test_givenTimelockDisabled_allowsEmergencyCancellation() public {
        uint64 actionId = _queueCollateralFactorUpdate();

        vm.prank(emergency);
        configTimelock.disable("");

        assertFalse(configTimelock.isEnabled(), "disabled");
        vm.prank(emergency);
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit TimelockActionCancelled(actionId, emergency);
        configTimelock.cancelQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given a queued action
    //  when caller has emergency role at any timestamp before finalization
    //   then it cancels the action and clears sub-actions
    function test_givenEmergencyCaller_cancelsAction(uint48 elapsed_) public {
        uint64 actionId = _queueCollateralFactorUpdate();
        uint256 queuedAt = block.timestamp;
        elapsed_ = uint48(bound(elapsed_, 0, type(uint48).max));
        vm.warp(queuedAt + elapsed_);

        vm.prank(emergency);
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit TimelockActionCancelled(actionId, emergency);
        configTimelock.cancelQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId);
        assertTrue(action.cancelled, "cancelled");
        assertEq(action.actions.length, 0, "sub-actions cleared");
    }

    // cancelQueuedAction
    // given a queued action has expected pre-state and projected post-state
    //  when emergency cancels the action
    //   then stale pre-state and post-state storage is cleared
    function test_givenQueuedAction_clearsStoredStateOnCancellation() public {
        vm.prank(admin);
        burnerLoans.setConfigurator(address(configTimelockHarness));

        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        ) = _collateralFactorUpdate();
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelockHarness.queueAction(
            address(burnerLoans),
            IBurnerLoans.setAssetRiskConfig.selector,
            abi.encode(address(usds), update, selection)
        );

        assertNotEq(
            configTimelockHarness.expectedPreStateHash(actionId, 0),
            bytes32(0),
            "pre-state stored"
        );
        (bool exists, address asset, IBurnerLoans.AssetConfig memory config) = configTimelockHarness
            .assetConfigPostState(actionId, 0);
        assertTrue(exists, "asset post-state stored");
        assertEq(asset, address(usds), "asset");
        assertEq(config.collateralFactorBps, 9_500, "post-state collateral factor");

        vm.prank(emergency);
        configTimelockHarness.cancelQueuedAction(actionId);

        assertEq(
            configTimelockHarness.expectedPreStateHash(actionId, 0),
            bytes32(0),
            "pre-state cleared"
        );
        (exists, asset, config) = configTimelockHarness.assetConfigPostState(actionId, 0);
        assertFalse(exists, "asset post-state cleared");
        assertEq(asset, address(0), "asset cleared");
        assertEq(config.collateralFactorBps, 0, "post-state config cleared");
    }

    // cancelQueuedAction
    // given a queued fee action has expected pre-state and projected post-state
    //  when emergency cancels the action
    //   then stale pre-state and fee post-state storage is cleared
    function test_givenQueuedFeeAction_clearsStoredStateOnCancellation() public {
        vm.prank(admin);
        burnerLoans.setConfigurator(address(configTimelockHarness));

        IBurnerLoans.AssetFeeConfig memory update;
        update.baseFeeBps = 50;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection;
        selection.baseFeeBps = true;

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelockHarness.queueAction(
            address(burnerLoans),
            IBurnerLoans.setAssetFeeConfig.selector,
            abi.encode(address(usds), update, selection)
        );

        assertNotEq(
            configTimelockHarness.expectedPreStateHash(actionId, 0),
            bytes32(0),
            "pre-state stored"
        );
        (
            bool exists,
            address asset,
            IBurnerLoans.AssetFeeConfig memory config
        ) = configTimelockHarness.feeConfigPostState(actionId, 0);
        assertTrue(exists, "fee post-state stored");
        assertEq(asset, address(usds), "asset");
        assertEq(config.baseFeeBps, 50, "post-state base fee");

        vm.prank(emergency);
        configTimelockHarness.cancelQueuedAction(actionId);

        assertEq(
            configTimelockHarness.expectedPreStateHash(actionId, 0),
            bytes32(0),
            "pre-state cleared"
        );
        (exists, asset, config) = configTimelockHarness.feeConfigPostState(actionId, 0);
        assertFalse(exists, "fee post-state cleared");
        assertEq(asset, address(0), "asset cleared");
        assertEq(config.baseFeeBps, 0, "post-state config cleared");
    }

    // cancelQueuedAction
    // given a cancelled same-asset batch had depended on an earlier queued risk action
    //  when a later risk action is queued
    //   then validation uses the earlier pending projection, not the cancelled batch post-state
    function test_givenCancelledRiskBatch_laterRiskActionUsesEarlierPendingProjection() public {
        vm.prank(admin);
        burnerLoans.setConfigurator(address(configTimelockHarness));

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory termUpdate;
        termUpdate.termLength = 14 days;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory termSelection;
        termSelection.termLength = true;

        vm.prank(burnerLoansAdmin);
        uint64 termActionId = configTimelockHarness.queueAction(
            address(burnerLoans),
            IBurnerLoans.setAssetRiskConfig.selector,
            abi.encode(address(usds), termUpdate, termSelection)
        );

        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory collateralFactorUpdate;
        collateralFactorUpdate.collateralFactorBps = 9_500;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory collateralFactorSelection;
        collateralFactorSelection.collateralFactorBps = true;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory minCrUpdate;
        minCrUpdate.minCollateralRatioBps = 12_000;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory minCrSelection;
        minCrSelection.minCollateralRatioBps = true;
        actions[0] = _singleAction(
            IBurnerLoans.setAssetRiskConfig.selector,
            abi.encode(address(usds), collateralFactorUpdate, collateralFactorSelection)
        );
        actions[1] = _singleAction(
            IBurnerLoans.setAssetRiskConfig.selector,
            abi.encode(address(usds), minCrUpdate, minCrSelection)
        );

        vm.prank(burnerLoansAdmin);
        uint64 cancelledBatchActionId = configTimelockHarness.queueBatch(actions);

        vm.prank(emergency);
        configTimelockHarness.cancelQueuedAction(cancelledBatchActionId);

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory horizonUpdate;
        horizonUpdate.maxMaturityHorizon = 21 days;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory horizonSelection;
        horizonSelection.maxMaturityHorizon = true;

        vm.prank(burnerLoansAdmin);
        uint64 horizonActionId = configTimelockHarness.queueAction(
            address(burnerLoans),
            IBurnerLoans.setAssetRiskConfig.selector,
            abi.encode(address(usds), horizonUpdate, horizonSelection)
        );

        assertEq(termActionId, 1, "term action id");
        assertEq(cancelledBatchActionId, 2, "cancelled batch action id");
        assertEq(horizonActionId, 3, "horizon action id");
    }
}
