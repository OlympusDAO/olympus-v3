// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockCancelTest is DepositManagerConfigTimelockTest {
    function test_givenQueuedRoute_whenEmergencyCancels_routeIsNotCreated() public {
        uint64 actionId = _queueAddRoute();
        uint256 receiptTokenIdCount = depositManager.getReceiptTokenIds().length;

        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(actionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR).isConfigured,
            "cancelled route creation should not configure the route"
        );
        assertEq(
            depositManager.getReceiptTokenIds().length,
            receiptTokenIdCount,
            "cancelled route creation should not mint a receipt token"
        );
    }

    function test_givenCallerIsNotEmergency_reverts(address caller_) public {
        vm.assume(caller_ != EMERGENCY);
        uint64 actionId = _queueDepositCap(iAsset, 100e18);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        vm.prank(caller_);
        _configTimelock.cancelQueuedAction(actionId);
    }

    function test_givenEmergency_cancelsAndReleasesConfigurationKey() public {
        uint64 firstActionId = _queueDepositCap(iAsset, 100e18);

        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(firstActionId);
        uint64 secondActionId = _queueDepositCap(iAsset, 200e18);

        assertEq(secondActionId, firstActionId + 1, "released key should allow requeue");
        assertTrue(
            _configTimelock.getQueuedAction(firstActionId).cancelled,
            "first action should be cancelled"
        );
    }

    function test_givenPoliciesAreInactive_emergencyCanCancel() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(_configTimelock));
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        vm.stopPrank();

        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(actionId);

        assertTrue(
            _configTimelock.getQueuedAction(actionId).cancelled,
            "emergency should cancel while policies are inactive"
        );
    }

    function test_givenEmergency_cancelsBatchAndReleasesEveryConfigurationKey() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _singleAction(
            IDepositManager.setAssetDepositCap.selector,
            abi.encode(iAsset, uint256(100e18))
        );
        actions[1] = _singleAction(
            IDepositManager.disableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 batchActionId = _configTimelock.queueBatch(actions);
        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(batchActionId);

        uint64 capActionId = _queueDepositCap(iAsset, 200e18);
        uint64 periodActionId = _queuePeriod(false);

        assertEq(capActionId, batchActionId + 1, "asset limits key should be released");
        assertEq(periodActionId, batchActionId + 2, "asset period key should be released");
    }

    function test_givenActionNotFound_reverts() public {
        uint64 actionId = _configTimelock.nextActionId();

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                actionId
            )
        );
        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(actionId);
    }

    function test_givenActionAlreadyExecuted_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        _warpReady();
        _configTimelock.executeQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(actionId);
    }

    function test_givenActionAlreadyCancelled_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.startPrank(EMERGENCY);
        _configTimelock.cancelQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        _configTimelock.cancelQueuedAction(actionId);
        vm.stopPrank();
    }

    function test_givenActionIsExpired_cancelsAndReleasesConfigurationKey() public {
        uint64 firstActionId = _queueDepositCap(iAsset, 100e18);
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(
            firstActionId
        );
        vm.warp(uint256(action.expiresAt) + 1);

        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(firstActionId);
        uint64 secondActionId = _queueDepositCap(iAsset, 200e18);

        assertEq(secondActionId, firstActionId + 1, "expired action key should be released");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
