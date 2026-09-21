// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; setup and revert-path calls ignore unused returns.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {Actions} from "src/Kernel.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockExecuteTest is DepositManagerConfigTimelockTest {
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

    function test_givenQueuedRoute_whenOperatorRoleRevoked_revertsAsStale() public {
        uint64 actionId = _queueAddRoute();
        vm.prank(ADMIN);
        rolesAdmin.revokeRole("deposit_operator", DEPOSIT_OPERATOR);
        _warpReady();

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
        );
        _configTimelock.executeQueuedAction(actionId);

        assertFalse(
            depositManager.isAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR).isConfigured,
            "route should not be created when the operator role is revoked"
        );
    }

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

    function test_givenQueuedRoute_whenAdminCreatesDirectly_revertsAsStale() public {
        uint64 actionId = _queueAddRoute();
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, SECOND_PERIOD, DEPOSIT_OPERATOR);
        _warpReady();

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
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
    }

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

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
        );
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
    }

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

    function test_givenDepositManagerIsDisabled_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(EMERGENCY);
        depositManager.disable("");
        _warpReady();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        _configTimelock.executeQueuedAction(actionId);
    }

    function test_givenTimelockIsDisabled_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(EMERGENCY);
        _configTimelock.disable("");
        _warpReady();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        _configTimelock.executeQueuedAction(actionId);
    }

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

    function test_givenDepositManagerPolicyIsInactive_reverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        _warpReady();

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(depositManager)
            )
        );
        _configTimelock.executeQueuedAction(actionId);
    }

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
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
