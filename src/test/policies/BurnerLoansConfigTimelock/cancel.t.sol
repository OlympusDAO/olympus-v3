// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
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
}
