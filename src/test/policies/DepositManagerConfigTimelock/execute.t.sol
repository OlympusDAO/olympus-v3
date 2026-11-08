// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";

// Shared domain values use constants; setup and revert-path calls ignore unused returns.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

contract DepositManagerConfigTimelockExecuteTest is DepositManagerConfigTimelockTest {
    // Scenarios: DMCT-EXECUTE-D06.
    function test_givenForeignKernelAndPausedManager_whenExecuted_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        _pausePolicy(address(depositManager));
        _warpReady();
        address foreignKernel = makeAddr("foreignKernel");
        vm.mockCall(
            address(depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encode(foreignKernel)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(depositManager),
                address(kernel),
                foreignKernel
            )
        );
        _configTimelock.executeQueuedAction(actionId);
        _assertPending(actionId);
    }

    // Scenarios: DMCT-EXECUTE-D07.
    function test_givenManagerStatusGetterReverts_whenExecuted_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        _warpReady();
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeCall(IEnabler.isEnabled, ()),
            hex"deadbeef"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
        _configTimelock.executeQueuedAction(actionId);
        _assertPending(actionId);
    }

    // Scenarios: DMCT-EXECUTE-D08.
    function test_givenManagerStatusMalformed_whenExecuted_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        _warpReady();
        vm.mockCall(address(depositManager), abi.encodeCall(IEnabler.isEnabled, ()), hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(depositManager)
            )
        );
        _configTimelock.executeQueuedAction(actionId);
        _assertPending(actionId);
    }

    function test_givenQueuedRoute_whenMatured_permissionlessExecutionEnablesRoute(
        address executor_
    ) public {
        uint64 actionId = _queueAddRoute();
        _warpReady();

        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        IDepositManager.AssetPeriodStatus memory status = depositManager.isAssetPeriod(
            iAsset,
            SECOND_PERIOD,
            DEPOSIT_OPERATOR
        );
        assertTrue(status.isConfigured, "route should be configured after execution");
        assertTrue(status.isEnabled, "timelocked route creation should start enabled");
    }

    // Scenarios: DMCT-EXECUTE-D03.
    function test_givenQueuedRoute_whenOperatorRoleRevoked_revertsAsStale() public {
        uint64 actionId = _queueAddRoute();
        vm.prank(ADMIN);
        rolesAdmin.revokeRole("deposit_operator", DEPOSIT_OPERATOR);
        _warpReady();

        _expectStale(
            actionId,
            0,
            keccak256(abi.encode(false, false, false, address(_configTimelock)))
        );
        _configTimelock.executeQueuedAction(actionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR).isConfigured,
            "route should not be created when the operator role is revoked"
        );
        _assertPending(actionId);
    }

    // Scenarios: DMCT-EXECUTE-D04.
    function test_givenQueuedRoute_whenOperatorRoleRevokedAndRegranted_succeeds() public {
        uint64 actionId = _queueAddRoute();
        vm.startPrank(ADMIN);
        rolesAdmin.revokeRole("deposit_operator", DEPOSIT_OPERATOR);
        rolesAdmin.grantRole("deposit_operator", DEPOSIT_OPERATOR);
        vm.stopPrank();
        _warpReady();

        _configTimelock.executeQueuedAction(actionId);

        assertTrue(
            depositManager.isAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR).isConfigured,
            "route should be created after role regrant"
        );
    }

    // Scenarios: DMCT-EXECUTE-D05.
    function test_givenQueuedRoute_whenAdminCreatesDirectly_revertsAsStale() public {
        uint64 actionId = _queueAddRoute();
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR);
        _warpReady();

        _expectStale(
            actionId,
            0,
            keccak256(abi.encode(true, true, true, address(_configTimelock)))
        );
        _configTimelock.executeQueuedAction(actionId);

        IDepositManager.AssetPeriodStatus memory status = depositManager.isAssetPeriod(
            iAsset,
            SECOND_PERIOD,
            DEPOSIT_OPERATOR
        );
        assertTrue(status.isConfigured, "directly created route should remain configured");
        assertTrue(status.isEnabled, "directly created route should remain enabled");
        assertEq(depositManager.getReceiptTokenIds().length, 2, "no duplicate token should exist");
        _assertPending(actionId);
    }

    // Scenarios: DMCT-EXECUTE-P04.
    function test_givenBatchWithRouteCreation_whenMatured_permissionlessExecutionIsAtomic(
        address executor_
    ) public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _singleAction(
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
        );
        actions[1] = _singleAction(
            IDepositManager.disableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );

        vm.prank(ADMIN);
        uint64 actionId = _configTimelock.queueBatch(actions);
        _warpReady();

        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertTrue(
            depositManager.isAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "timelocked route should be created and enabled"
        );
        assertFalse(
            depositManager.isAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR).isEnabled,
            "pre-existing route should be disabled"
        );
    }

    // Scenarios: DMCT-EXECUTE-T02.
    function test_givenBatchWithRouteCreation_whenLaterActionIsStale_rollsBackCreation() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _singleAction(
            IDepositManager.addAssetPeriod.selector,
            abi.encode(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR)
        );
        actions[1] = _singleAction(
            IDepositManager.disableAssetPeriod.selector,
            abi.encode(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR)
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueBatch(actions);

        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        uint256 receiptTokenCount = depositManager.getReceiptTokenIds().length;
        _warpReady();

        _expectStale(actionId, 1, keccak256(abi.encode(true, false, address(_configTimelock))));
        _configTimelock.executeQueuedAction(actionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR).isConfigured,
            "route creation should roll back when a later sub-action is stale"
        );
        assertEq(
            depositManager.getReceiptTokenIds().length,
            receiptTokenCount,
            "receipt-token creation should roll back with the batch"
        );
        _assertPending(actionId);
    }

    // Scenarios: DMCT-EXECUTE-N01.
    function test_givenBeforeDelay_reverts(uint48 elapsed_) public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(actionId);
        uint256 elapsed = bound(elapsed_, 0, _configTimelock.timelockDelay() - 1);
        vm.warp(uint256(action.queuedAt) + elapsed);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                actionId,
                action.executableAt
            )
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    // Scenarios: DMCT-EXECUTE-A01.
    function test_givenWithinExecutionWindow_executes(address executor_, uint48 elapsed_) public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(actionId);
        uint256 elapsed = bound(
            elapsed_,
            _configTimelock.timelockDelay(),
            _configTimelock.timelockDelay() + _configTimelock.EXECUTION_WINDOW()
        );
        vm.warp(uint256(action.queuedAt) + elapsed);

        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            100e18,
            "execution should update deposit cap"
        );
    }

    function test_givenExecutionWindowExpired_reverts(uint48 elapsedAfterExpiry_) public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(actionId);
        uint256 elapsedAfterExpiry = bound(elapsedAfterExpiry_, 1, 365 days);
        vm.warp(uint256(action.expiresAt) + elapsedAfterExpiry);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    // Scenarios: DMCT-EXECUTE-L02.
    function test_givenDepositManagerIsDisabled_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(EMERGENCY);
        depositManager.disable("");
        _warpReady();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        _configTimelock.executeQueuedAction(actionId);
    }

    // Scenarios: DMCT-EXECUTE-L01.
    function test_givenTimelockIsDisabled_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(EMERGENCY);
        _configTimelock.disable("");
        _warpReady();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        _configTimelock.executeQueuedAction(actionId);
    }

    // Scenarios: DMCT-EXECUTE-L03.
    function test_givenTimelockPolicyIsInactive_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(_configTimelock));
        _warpReady();

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    // Scenarios: DMCT-EXECUTE-L04.
    function test_givenDepositManagerPolicyIsInactive_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        _warpReady();

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(depositManager)
            )
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    // Scenarios: DMCT-EXECUTE-L05.
    function test_givenPoliciesAreReactivated_executes() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(_configTimelock));
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(_configTimelock));
        vm.stopPrank();
        _warpReady();

        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            100e18,
            "reactivated policies should permit queued execution"
        );
    }

    // Scenarios: DMCT-EXECUTE-D01.
    function test_givenConfigOperatorChanged_executionReverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        _warpReady();

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    // Scenarios: DMCT-EXECUTE-D02.
    function test_givenConfigOperatorChangedAwayAndBack_executionSucceeds(
        address executor_,
        uint48 elapsed_
    ) public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        ITimelockBatchQueue.QueuedAction memory original = _configTimelock.getQueuedAction(
            actionId
        );
        (, bytes32 hashBefore) = _configTimelock.getQueuedConfigState(actionId, 0, 0);
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        vm.warp(bound(elapsed_, original.executableAt, original.expiresAt));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);
        _assertPending(actionId);
        (, bytes32 hashAfter) = _configTimelock.getQueuedConfigState(actionId, 0, 0);
        assertEq(hashAfter, hashBefore, "lost authority preserves original commitment");
        assertEq(
            _configTimelock.getQueuedAction(actionId).expiresAt,
            original.expiresAt,
            "lost authority preserves original expiry"
        );
        vm.prank(ADMIN);
        depositManager.setConfigOperator(address(_configTimelock));
        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            100e18,
            "restored operator should permit queued execution"
        );
    }

    // Scenarios: DMCT-EXECUTE-P01.
    function test_givenTimelockIsReEnabled_queuesAndExecutes() public {
        vm.prank(EMERGENCY);
        _configTimelock.disable("");
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();

        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        _warpReady();
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            100e18,
            "re-enabled timelock should remain operational"
        );
    }

    // Scenarios: DMCT-EXECUTE-I01.
    function test_whenUnknownExecution_reverts(address caller_, uint64 id_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        vm.prank(caller_);
        _configTimelock.executeQueuedAction(id_);
    }

    // Scenarios: DMCT-EXECUTE-I01.
    function test_whenUnknownExecutionBoundaryIds_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                uint64(0)
            )
        );
        _configTimelock.executeQueuedAction(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                type(uint64).max
            )
        );
        _configTimelock.executeQueuedAction(type(uint64).max);
    }

    // Scenarios: DMCT-EXECUTE-I02.
    function test_givenExecuted_whenExecutedAgain_reverts() public {
        uint64 id = _queueDepositCap(iAsset, 1);
        _warpReady();
        _configTimelock.executeQueuedAction(id);
        _pausePolicy(address(_configTimelock));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            )
        );
        _configTimelock.executeQueuedAction(id);
    }

    // Scenarios: DMCT-EXECUTE-I03.
    function test_givenCancelled_whenExecuted_reverts() public {
        uint64 id = _queueDepositCap(iAsset, 1);
        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(id);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                id
            )
        );
        _configTimelock.executeQueuedAction(id);
    }

    // Scenarios: DMCT-EXECUTE-N02.
    function test_whenExecutionAtReady() public {
        _executeAtOffset(0);
    }

    // Scenarios: DMCT-EXECUTE-N02.
    function test_whenExecutionJustAfterReady() public {
        _executeAtOffset(1);
    }

    // Scenarios: DMCT-EXECUTE-N02.
    function test_whenExecutionJustBeforeExpiry() public {
        _executeAtOffset(3 days - 1);
    }

    // Scenarios: DMCT-EXECUTE-N02.
    function test_whenExecutionAtExpiry() public {
        _executeAtOffset(3 days);
    }

    // Scenarios: DMCT-EXECUTE-N01.
    function test_givenPaused_whenExecutionJustBeforeReady_reverts() public {
        uint64 id = _queueDepositCap(iAsset, 1);
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(id);
        _pausePolicy(address(_configTimelock));
        vm.warp(uint256(action.executableAt) - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                id,
                action.executableAt
            )
        );
        _configTimelock.executeQueuedAction(id);
        _assertPending(id);
    }

    // Scenarios: DMCT-EXECUTE-N03.
    function test_whenExecutionAfterExpiry_reverts(uint256 now_) public {
        uint64 id = _queueDepositCap(iAsset, 1);
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(id);
        vm.warp(bound(now_, uint256(action.expiresAt) + 1, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                id,
                action.expiresAt
            )
        );
        _configTimelock.executeQueuedAction(id);
        _assertPending(id);
    }

    // Scenarios: DMCT-EXECUTE-T01.
    function test_whenTargetSetterReverts_revertsAtomically() public {
        uint64 id = _queueDepositCap(iAsset, 1);
        bytes32 targetBefore = _targetState();
        _warpReady();
        bytes memory errorData = abi.encodeWithSelector(
            IAssetManager.AssetManager_NotConfigured.selector
        );
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeCall(depositManager.setAssetDepositCap, (iAsset, 1)),
            errorData
        );
        vm.expectRevert(errorData);
        _configTimelock.executeQueuedAction(id);
        _assertPending(id);
        assertEq(_targetState(), targetBefore, "target failure preserves all target state");
    }

    // Scenarios: DMCT-EXECUTE-P03.
    function test_whenCapUnchanged_executesAndReleasesKey() public {
        uint64 id = _queueDepositCap(iAsset, type(uint256).max);
        _warpReady();
        _configTimelock.executeQueuedAction(id);
        _assertReleased(id, 0, _limitsKey(iAsset));
        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            type(uint256).max,
            "no-op configuration remains unchanged"
        );
    }

    // Scenarios: DMCT-EXECUTE-P02.
    function test_whenExecuted_emitsExactEventsAndReleasesState(address caller_) public {
        uint64 id = _queueDepositCap(iAsset, 1);
        ITimelockBatchQueue.QueuedAction memory beforeAction = _configTimelock.getQueuedAction(id);
        _warpReady();
        vm.expectEmit(true, true, false, true, address(depositManager));
        emit IAssetManager.AssetDepositCapSet(address(iAsset), 1);
        vm.expectEmit(true, true, true, true, address(_configTimelock));
        emit ITimelockBatchQueue.TimelockSubActionExecuted(
            id,
            address(depositManager),
            IDepositManager.setAssetDepositCap.selector,
            0
        );
        vm.expectEmit(true, true, false, true, address(_configTimelock));
        emit ITimelockBatchQueue.TimelockActionExecuted(id, caller_);
        vm.prank(caller_);
        _configTimelock.executeQueuedAction(id);
        _assertReleased(id, 0, _limitsKey(iAsset));
        ITimelockBatchQueue.QueuedAction memory afterAction = _configTimelock.getQueuedAction(id);
        assertTrue(afterAction.executed, "executed terminal flag");
        assertFalse(afterAction.cancelled, "execution does not cancel");
        assertEq(
            afterAction.proposer,
            beforeAction.proposer,
            "execution retains original proposer"
        );
        assertEq(afterAction.queuedAt, beforeAction.queuedAt, "queue timestamp retained");
        assertEq(afterAction.executableAt, beforeAction.executableAt, "ready timestamp retained");
        assertEq(afterAction.expiresAt, beforeAction.expiresAt, "expiry retained");
        assertEq(_configTimelock.nextActionId(), id + 1, "execution consumes no further ID");
        uint64 next = _queueDepositCap(iAsset, 2);
        assertEq(next, id + 1, "released key permits another action");
    }

    function _executeAtOffset(uint48 offset_) private {
        uint64 id = _queueDepositCap(iAsset, 1);
        ITimelockBatchQueue.QueuedAction memory action = _configTimelock.getQueuedAction(id);
        vm.warp(uint256(action.executableAt) + offset_);
        _configTimelock.executeQueuedAction(id);
        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            1,
            "inclusive execution boundary"
        );
        _assertReleased(id, 0, _limitsKey(iAsset));
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
