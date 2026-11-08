// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE, EMERGENCY_ROLE as CANCEL_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

contract DepositManagerConfigTimelockCancelTest is DepositManagerConfigTimelockTest {
    // Scenarios: DMCT-CANCEL-P04.
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

    // Scenarios: DMCT-CANCEL-A02.
    function test_givenCallerIsNotEmergency_reverts(address caller_, bool paused_) public {
        vm.assume(caller_ != EMERGENCY);
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        if (paused_) _pausePolicy(address(_configTimelock));

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        vm.prank(caller_);
        _configTimelock.cancelQueuedAction(actionId);
    }

    // Scenarios: DMCT-CANCEL-P02.
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

    // Scenarios: DMCT-CANCEL-L03.
    function test_givenPoliciesAreInactive_whenEmergencyCancels_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(_configTimelock));
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(actionId);

        _assertPending(actionId);
    }

    // Scenarios: DMCT-CANCEL-P03.
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
        uint64 periodActionId = _queueDisablePeriod();

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

    // Scenarios: DMCT-CANCEL-I02.
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

    // Scenarios: DMCT-CANCEL-I03.
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

    // Scenarios: DMCT-CANCEL-N01.
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

    // Scenarios: DMCT-CANCEL-L01.
    function test_givenQueuedAction_emergencyCancelsWhileDisabled() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(EMERGENCY);
        _configTimelock.disable("");

        bytes32 targetBefore = _targetState();
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            hex"deadbeef"
        );
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("isEnabled()"),
            hex"deadbeef"
        );
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeWithSignature("configOperator()"),
            hex"deadbeef"
        );
        vm.warp(uint256(_configTimelock.getQueuedAction(actionId).expiresAt) + 1);
        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(actionId);
        _assertReleased(actionId, 0, _limitsKey(iAsset));
        assertEq(
            _targetState(),
            targetBefore,
            "Cancellation preserves target accounting and custody"
        );

        assertTrue(
            _configTimelock.getQueuedAction(actionId).cancelled,
            "emergency should cancel while disabled"
        );
    }

    // Scenarios: DMCT-CANCEL-A01, DMCT-CANCEL-P01.
    function test_givenEmergencyOnly_whenCancelled(address caller_) public {
        vm.assume(caller_ != ADMIN);
        _grantRole(CANCEL_ROLE, caller_);
        _cancelSucceeds(caller_);
    }

    // Scenarios: DMCT-CANCEL-A01.
    function test_givenAdminAndEmergency_whenCancelled(address caller_) public {
        _grantRole(ADMIN_ROLE, caller_);
        _grantRole(CANCEL_ROLE, caller_);
        _cancelSucceeds(caller_);
    }

    // Scenarios: DMCT-CANCEL-I01.
    function test_whenUnknownActionCancelled_reverts(address caller_, uint64 id_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        vm.prank(caller_);
        _configTimelock.cancelQueuedAction(id_);
    }

    // Scenarios: DMCT-CANCEL-I01.
    function test_whenUnknownActionBoundaryIds_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                uint64(0)
            )
        );
        _configTimelock.cancelQueuedAction(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                type(uint64).max
            )
        );
        _configTimelock.cancelQueuedAction(type(uint64).max);
    }

    // Scenarios: DMCT-CANCEL-L02.
    function test_givenBothPoliciesPausedInactive_whenCancelled_reverts() public {
        uint64 id = _queueDepositCap(iAsset, 1);
        _pausePolicy(address(_configTimelock));
        _pausePolicy(address(depositManager));
        _setPolicyActive(address(_configTimelock), false);
        _setPolicyActive(address(depositManager), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(id);
        _assertPending(id);
    }

    // Scenarios: DMCT-CANCEL-D01.
    function test_givenOperatorRotatedAndStale_whenCancelled() public {
        uint64 id = _queueDepositCap(iAsset, 1);
        vm.startPrank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        depositManager.setAssetMinimumDeposit(iAsset, 2);
        vm.stopPrank();
        bytes32 targetBefore = _targetState();
        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(id);
        _assertReleased(id, 0, _limitsKey(iAsset));
        assertEq(_targetState(), targetBefore, "cancel ignores stale state without changing it");
    }

    // Scenarios: DMCT-CANCEL-N01.
    function test_whenCancellationTimeVaries(uint256 now_) public {
        uint64 id = _queueDepositCap(iAsset, 1);
        vm.warp(bound(now_, vm.getBlockTimestamp(), type(uint256).max));
        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(id);
        _assertReleased(id, 0, _limitsKey(iAsset));
    }

    // Scenarios: DMCT-CANCEL-A03.
    function test_givenEmergencyRoleRevoked_whenCancelled_reverts() public {
        uint64 id = _queueDepositCap(iAsset, 1);
        vm.prank(ADMIN);
        rolesAdmin.revokeRole(CANCEL_ROLE, EMERGENCY);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, CANCEL_ROLE));
        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(id);
        _assertPending(id);
    }

    function _cancelSucceeds(address caller_) private {
        uint64 id = _queueDepositCap(iAsset, 1);
        ITimelockBatchQueue.QueuedAction memory beforeAction = _configTimelock.getQueuedAction(id);
        bytes32 targetBefore = _targetState();
        uint64 next = _configTimelock.nextActionId();
        vm.expectEmit(true, true, false, true, address(_configTimelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(id, caller_);
        vm.recordLogs();
        vm.prank(caller_);
        _configTimelock.cancelQueuedAction(id);
        assertEq(vm.getRecordedLogs().length, 1, "exactly one cancellation event");
        ITimelockBatchQueue.QueuedAction memory afterAction = _configTimelock.getQueuedAction(id);
        assertTrue(afterAction.cancelled, "cancelled terminal flag");
        assertFalse(afterAction.executed, "not executed");
        assertEq(afterAction.proposer, beforeAction.proposer, "proposer retained");
        assertEq(afterAction.queuedAt, beforeAction.queuedAt, "queue time retained");
        assertEq(afterAction.executableAt, beforeAction.executableAt, "ready time retained");
        assertEq(afterAction.expiresAt, beforeAction.expiresAt, "expiry retained");
        assertEq(_configTimelock.nextActionId(), next, "cancel consumes no ID");
        _assertReleased(id, 0, _limitsKey(iAsset));
        assertEq(_targetState(), targetBefore, "cancel preserves target state and custody");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
