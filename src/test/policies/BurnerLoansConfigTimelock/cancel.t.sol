// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.
// forge-lint: disable-start(unused-return,unsafe-typecast)

contract BurnerLoansConfigTimelockCancelTest is BurnerLoansConfigTimelockTest {
    /// @notice The frozen cancellation gate also preserves surplus and pending-rescue conflict keys.
    // Finite rescue selector and timelock lifecycle combinations; quantities are token base units.
    // forge-lint: disable-start(calls-loop,literal-instead-of-constant)
    // Scenarios: BLCT-C01.
    function test_givenTimelockUnavailable_whenEmergencyCancelsRescue_reverts() public {
        address destination = makeAddr("rescue destination");
        for (uint256 pending; pending < 2; ++pending) {
            for (uint256 inactive; inactive < 2; ++inactive) {
                uint256 snapshot = vm.snapshotState();
                MockRevertingTransferToken asset = new MockRevertingTransferToken(18);
                asset.mint(address(burnerLoans), 11);
                if (pending != 0) {
                    asset.setTransferReverts(alice, true);
                    burnerLoans.recordPendingSeizureRewardForTest(address(asset), alice, 10);
                }
                vm.prank(admin);
                uint64 id = pending == 0
                    ? configTimelock.queueRescue(address(asset), destination)
                    : configTimelock.queueRescuePendingPayout(
                        address(asset),
                        alice,
                        destination,
                        4
                    );
                bytes32 actionBefore = keccak256(abi.encode(configTimelock.getQueuedAction(id)));
                (bytes32 key, bytes32 stateHash) = configTimelock.getQueuedConfigState(id, 0, 0);
                vm.prank(admin);
                if (inactive == 0) configTimelock.disable("");
                else kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
                bytes memory failure = inactive == 0
                    ? abi.encodeWithSelector(IEnabler.NotEnabled.selector)
                    : abi.encodeWithSelector(
                        IBurnerLoansConfigTimelock
                            .BurnerLoansConfigTimelock_PolicyInactive
                            .selector,
                        address(configTimelock)
                    );
                vm.expectRevert(failure);
                vm.prank(emergency);
                configTimelock.cancelQueuedAction(id);
                assertEq(
                    keccak256(abi.encode(configTimelock.getQueuedAction(id))),
                    actionBefore,
                    "frozen rescue cancellation retains action"
                );
                assertEq(
                    configTimelock.pendingActionId(key),
                    id,
                    "frozen rescue cancellation retains key"
                );
                (, bytes32 afterHash) = configTimelock.getQueuedConfigState(id, 0, 0);
                assertEq(afterHash, stateHash, "frozen rescue cancellation retains guard");
                assertEq(
                    asset.balanceOf(address(burnerLoans)),
                    11,
                    "frozen rescue cancellation retains custody"
                );
                assertEq(
                    asset.balanceOf(destination),
                    0,
                    "frozen rescue cancellation pays nothing"
                );
                assertEq(
                    burnerLoans.pendingPayout(address(asset), alice),
                    pending == 0 ? 0 : 10,
                    "frozen cancellation retains entitlement"
                );
                assertTrue(vm.revertToState(snapshot), "restore frozen rescue cancellation");
            }
        }
    }

    // forge-lint: disable-end(calls-loop,literal-instead-of-constant)

    // cancelQueuedAction
    // given caller does not have emergency role
    //  when cancelling a queued action
    //   then it reverts
    function test_givenNonEmergencyCaller_reverts(address caller_) public {
        vm.assume(caller_ != emergency);
        uint64 actionId = _queueMaximumLtvUpdate();

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        configTimelock.cancelQueuedAction(actionId);
    }

    // cancelQueuedAction
    // given action has already been cancelled
    //  when executing at any later timestamp
    //   then execution reverts as cancelled
    function test_givenCancelledAction_reverts(uint48 elapsed_) public {
        uint64 actionId = _queueMaximumLtvUpdate();
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
        uint64 actionId = _queueMaximumLtvUpdate();
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
        uint64 actionId = _queueMaximumLtvUpdate();

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

    /// @notice Disablement or Kernel removal blocks emergency cancellation and retains the action.
    // Finite independent local and policy states.
    // forge-lint: disable-start(calls-loop)
    function test_givenTimelockUnavailable_whenEmergencyCancels_reverts() public {
        for (uint256 disabled; disabled < 2; ++disabled) {
            for (uint256 inactive; inactive < 2; ++inactive) {
                if (disabled == 0 && inactive == 0) continue;
                uint256 snapshot = vm.snapshotState();
                uint64 id = _queueMaximumLtvUpdate();
                bytes32 beforeAction = keccak256(abi.encode(configTimelock.getQueuedAction(id)));
                (bytes32 key, bytes32 stateHash) = configTimelock.getQueuedConfigState(id, 0, 0);
                vm.startPrank(admin);
                if (disabled != 0) configTimelock.disable("");
                if (inactive != 0)
                    kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
                vm.stopPrank();
                bytes memory failure = disabled != 0
                    ? abi.encodeWithSelector(IEnabler.NotEnabled.selector)
                    : abi.encodeWithSelector(
                        IBurnerLoansConfigTimelock
                            .BurnerLoansConfigTimelock_PolicyInactive
                            .selector,
                        address(configTimelock)
                    );
                vm.expectRevert(failure);
                vm.prank(emergency);
                configTimelock.cancelQueuedAction(id);
                assertEq(
                    keccak256(abi.encode(configTimelock.getQueuedAction(id))),
                    beforeAction,
                    "rejected cancellation preserves action"
                );
                assertEq(
                    configTimelock.pendingActionId(key),
                    id,
                    "rejected cancellation preserves key owner"
                );
                (, bytes32 afterHash) = configTimelock.getQueuedConfigState(id, 0, 0);
                assertEq(afterHash, stateHash, "rejected cancellation preserves guard");
                assertTrue(vm.revertToState(snapshot), "restore cancellation lifecycle");
            }
        }
    }

    // forge-lint: disable-end(calls-loop)

    // cancelQueuedAction
    // given a queued action
    //  when caller has emergency role at any timestamp before finalization
    //   then it cancels the action and clears sub-actions
    function test_givenEmergencyCaller_cancelsAction(uint48 elapsed_) public {
        uint64 actionId = _queueMaximumLtvUpdate();
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
}

// forge-lint: disable-end(unused-return,unsafe-typecast)
