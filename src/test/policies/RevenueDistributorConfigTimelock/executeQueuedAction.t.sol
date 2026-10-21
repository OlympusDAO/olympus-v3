// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";

contract RevenueDistributorConfigTimelockExecuteQueuedActionTest is
    RevenueDistributorConfigTimelockTest
{
    event TimelockActionExecuted(uint64 indexed actionId, address indexed executor);
    event TimelockSubActionExecuted(
        uint64 indexed actionId,
        address indexed target,
        bytes4 indexed selector,
        uint256 index
    );

    // Scenarios: RDT-E13
    function testFuzz_whenExecutionIsWithinWindow_anyCallerExecutes(
        address executor_,
        uint48 timestamp_
    ) public {
        uint64 actionId = _queueRoute(address(token));
        ITimelockBatchQueue.QueuedAction memory queued = configTimelock.getQueuedAction(actionId);
        bytes32 key = _queuedKey(actionId, 0);
        // bound() guarantees that the result fits uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        timestamp_ = uint48(bound(timestamp_, queued.executableAt, queued.expiresAt));
        vm.warp(timestamp_);

        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit TimelockSubActionExecuted(
            actionId,
            address(distributor),
            IRevenueDistributor.setAssetRoutes.selector,
            0
        );
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit TimelockActionExecuted(actionId, executor_);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory executed = configTimelock.getQueuedAction(actionId);
        assertTrue(executed.executed, "action marked executed");
        assertFalse(executed.cancelled, "action not cancelled");
        assertEq(executed.actions.length, 0, "sub-actions cleared");
        assertEq(configTimelock.pendingActionId(key), 0, "configuration key released");
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "route installed"
        );
    }

    // Scenarios: EXEC-I02
    function testFuzz_whenExecutionIsBeforeReady_revertsAndRetainsAction(
        address executor_,
        uint48 timestamp_
    ) public {
        uint64 actionId = _queueRoute(address(token));
        ITimelockBatchQueue.QueuedAction memory queued = configTimelock.getQueuedAction(actionId);
        bytes32 key = _queuedKey(actionId, 0);
        // bound() guarantees that the result fits uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        timestamp_ = uint48(bound(timestamp_, queued.queuedAt, queued.executableAt - 1));
        vm.warp(timestamp_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                actionId,
                queued.executableAt
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            keccak256(abi.encode(configTimelock.getQueuedAction(actionId))),
            keccak256(abi.encode(queued)),
            "queued action retained"
        );
        assertEq(configTimelock.pendingActionId(key), actionId, "configuration key retained");
    }

    // Scenarios: EXEC-I06
    function testFuzz_whenExecutionIsExpired_revertsAndRetainsAction(
        address executor_,
        uint48 timestamp_
    ) public {
        uint64 actionId = _queueRoute(address(token));
        ITimelockBatchQueue.QueuedAction memory queued = configTimelock.getQueuedAction(actionId);
        bytes32 key = _queuedKey(actionId, 0);
        // bound() guarantees that the result fits uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        timestamp_ = uint48(bound(timestamp_, uint256(queued.expiresAt) + 1, type(uint48).max));
        vm.warp(timestamp_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                queued.expiresAt
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            keccak256(abi.encode(configTimelock.getQueuedAction(actionId))),
            keccak256(abi.encode(queued)),
            "expired action retained"
        );
        assertEq(configTimelock.pendingActionId(key), actionId, "expired key retained");
    }

    // Scenarios: EXEC-I01
    function testFuzz_whenActionDoesNotExist_revertsBeforeLifecycleChecks(
        address executor_,
        uint64 actionId_
    ) public {
        vm.prank(emergency);
        configTimelock.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                actionId_
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId_);
    }

    // Scenarios: EXEC-I07
    function testFuzz_whenActionWasCancelled_revertsBeforeLifecycleChecks(
        address executor_
    ) public {
        uint64 actionId = _queueRoute(address(token));
        vm.prank(emergency);
        configTimelock.cancelQueuedAction(actionId);
        vm.prank(emergency);
        configTimelock.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
    }

    // Scenarios: EXEC-I08
    function testFuzz_whenActionAlreadyExecuted_revertsBeforeLifecycleChecks(
        address executor_
    ) public {
        uint64 actionId = _queueRoute(address(token));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);
        configTimelock.executeQueuedAction(actionId);
        vm.prank(emergency);
        configTimelock.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
    }

    // Scenarios: EXEC-V01
    function testFuzz_whenExecutedOrUnknownActionRead_returnsTerminalStateAndDefaults(
        address caller_,
        bool maximumUnknownId_
    ) public {
        uint64 actionId = _queueRoute(address(token));
        bytes32 key = _queuedKey(actionId, 0);
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);
        configTimelock.executeQueuedAction(actionId);
        uint64 unknownId = maximumUnknownId_ ? type(uint64).max : 0;

        vm.startPrank(caller_);
        ITimelockBatchQueue.QueuedAction memory executed = configTimelock.getQueuedAction(actionId);
        assertTrue(executed.executed, "getter reports executed terminal state");
        assertFalse(executed.cancelled, "executed action is not cancelled");
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        // The expected revert prevents use of the returned length.
        // forge-lint: disable-next-line(unused-return)
        configTimelock.getQueuedActionLength(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                unknownId
            )
        );
        // The expected revert prevents use of the returned action.
        // forge-lint: disable-next-line(unused-return)
        configTimelock.getQueuedAction(unknownId);
        assertEq(
            configTimelock.getQueuedConfigStateCount(unknownId, 0),
            0,
            "unknown action has no guard state"
        );
        assertEq(
            configTimelock.getQueuedConfigDestination(unknownId, 0),
            address(0),
            "unknown action has no guard destination"
        );
        assertEq(configTimelock.pendingActionId(key), 0, "executed action released key");
        vm.stopPrank();
    }

    // given a route queued while the distributor is enabled
    //   when the distributor is disabled before execution
    //     [X] execution reverts and leaves the queued action intact
    function test_givenTargetDisabledAfterQueue_whenRouteExecuted_reverts() public {
        uint64 actionId = _queueRoute(address(token));
        bytes32 key = _queuedKey(actionId, 0);
        vm.prank(admin);
        distributor.disable("");
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.executeQueuedAction(actionId);
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "disabled target cannot install queued route"
        );
        assertEq(configTimelock.pendingActionId(key), actionId, "failed action retains key");

        vm.prank(admin);
        distributor.reEnable();
        configTimelock.executeQueuedAction(actionId);
        assertEq(configTimelock.pendingActionId(key), 0, "successful retry releases key");
    }

    // Scenarios: EXEC-L02
    function testFuzz_givenTargetDisabledAfterQueue_whenConfigurationExecuted_revertsThenRetries(
        uint8 actionKind_,
        address executor_
    ) public {
        // bound() guarantees that the result fits uint8.
        // forge-lint: disable-next-line(unsafe-typecast)
        actionKind_ = uint8(bound(actionKind_, 0, 2));
        uint64 actionId = _queueConfiguration(actionKind_);
        bytes32 key = _queuedKey(actionId, 0);
        bytes32 actionBefore = keccak256(abi.encode(configTimelock.getQueuedAction(actionId)));
        vm.prank(admin);
        distributor.disable("");
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            keccak256(abi.encode(configTimelock.getQueuedAction(actionId))),
            actionBefore,
            "disabled target preserves action"
        );
        assertEq(configTimelock.pendingActionId(key), actionId, "disabled target retains key");

        vm.prank(admin);
        distributor.reEnable();
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(configTimelock.pendingActionId(key), 0, "successful retry releases key");
    }

    // Scenarios: EXEC-L05
    function testFuzz_givenTargetInactiveAfterQueue_whenExecuted_revertsThenRetries(
        address executor_,
        bool locallyEnabled_
    ) public {
        uint64 actionId = _queueRoute(address(token));
        bytes32 key = _queuedKey(actionId, 0);
        if (!locallyEnabled_) {
            vm.prank(admin);
            distributor.disable("");
        }
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        if (locallyEnabled_) {
            vm.expectRevert(IRevenueDistributor.RevenueDistributor_PolicyInactive.selector);
        } else {
            vm.expectRevert(IEnabler.NotEnabled.selector);
        }
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(configTimelock.pendingActionId(key), actionId, "failed action retains key");
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "action remains live");

        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        if (!locallyEnabled_) {
            vm.prank(admin);
            distributor.reEnable();
        }
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);
        assertEq(configTimelock.pendingActionId(key), 0, "successful retry releases key");
    }

    // Scenarios: RDT-E11
    function testFuzz_givenTimelockDisabled_whenExecuted_reverts(address executor_) public {
        uint64 actionId = _queueRoute(address(token));
        bytes32 key = _queuedKey(actionId, 0);
        vm.prank(emergency);
        configTimelock.disable("");
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(configTimelock.pendingActionId(key), actionId, "disabled failure retains key");
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "action remains live");
    }

    // Scenarios: RDT-E12
    function testFuzz_givenTimelockInactive_whenExecuted_reverts(address executor_) public {
        uint64 actionId = _queueRoute(address(token));
        bytes32 key = _queuedKey(actionId, 0);
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_PolicyInactive
                    .selector,
                address(configTimelock)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(configTimelock.pendingActionId(key), actionId, "inactive failure retains key");
        assertFalse(configTimelock.getQueuedAction(actionId).executed, "action remains live");
    }

    /// @notice Execution rechecks the selected operator and retains a valid queued route on rejection.
    function test_givenOperatorRotatedAfterQueue_whenExecuted_reverts() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, routes);
        vm.prank(admin);
        distributor.setConfigOperator(alice);
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);
        bytes32 beforeAction = keccak256(abi.encode(configTimelock.getQueuedAction(actionId)));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(configTimelock)
            )
        );
        configTimelock.executeQueuedAction(actionId);
        assertEq(
            keccak256(abi.encode(configTimelock.getQueuedAction(actionId))),
            beforeAction,
            "rotation failure preserves action"
        );
    }

    // Scenarios: EXEC-L04
    function testFuzz_givenOperatorRotatedAfterQueue_whenConfigurationExecuted_reverts(
        uint8 actionKind_,
        address executor_
    ) public {
        // bound() guarantees that the result fits uint8.
        // forge-lint: disable-next-line(unsafe-typecast)
        actionKind_ = uint8(bound(actionKind_, 0, 2));
        uint64 actionId = _queueConfiguration(actionKind_);
        bytes32 key = _queuedKey(actionId, 0);
        bytes32 beforeAction = keccak256(abi.encode(configTimelock.getQueuedAction(actionId)));
        vm.prank(admin);
        distributor.setConfigOperator(alice);
        vm.warp(configTimelock.getQueuedAction(actionId).executableAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(configTimelock)
            )
        );
        vm.prank(executor_);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            keccak256(abi.encode(configTimelock.getQueuedAction(actionId))),
            beforeAction,
            "rotation failure preserves action"
        );
        assertEq(configTimelock.pendingActionId(key), actionId, "rotation failure retains key");
    }

    function _queueConfiguration(uint8 actionKind_) internal returns (uint64 actionId) {
        address yieldRecipient = actionKind_ == 2 ? address(_activeYieldRecipient()) : address(0);
        vm.startPrank(admin);
        if (actionKind_ == 0) {
            actionId = configTimelock.queueSetAssetRoutes(address(token), 0, _emptyRoutes());
        } else if (actionKind_ == 1) {
            distributor.setAssetRoutes(address(token), 0, _emptyRoutes());
            actionId = configTimelock.queueDisableAssetRoutes(address(token));
        } else {
            actionId = configTimelock.queueSetYieldRecipient(yieldRecipient);
        }
        vm.stopPrank();
    }
}
