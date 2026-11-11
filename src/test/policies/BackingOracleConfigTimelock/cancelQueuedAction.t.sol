// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Contracts
import {BackingOracleConfigTimelockTest, ITimelockBatchQueue, ROLESv1, IPolicyAdmin} from "./fixtures/BackingOracleConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";

// Constants
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BackingOracleCancelQueuedActionTest is BackingOracleConfigTimelockTest {
    function _rejectMissing(uint64 id_) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        _timelock.cancelQueuedAction(id_);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-05.
    function test_whenAbsentBoundarySeeds_reverts() public {
        _rejectMissing(0);
        _rejectMissing(1);
        _rejectMissing(type(uint64).max);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-01.
    function test_whenEmergencyCancels(
        bool queueEnabled_,
        bool targetEnabled_,
        uint48 elapsed_
    ) public givenEnabled {
        uint64 id = _queue(110e18);
        if (!queueEnabled_) {
            vm.prank(_ADMIN);
            _timelock.disable("");
        }
        if (!targetEnabled_) {
            vm.prank(_ADMIN);
            _oracle.disable("");
        }
        assertEq(_timelock.isEnabled(), queueEnabled_, "independent queue enablement precondition");
        assertEq(_oracle.isEnabled(), targetEnabled_, "independent target enablement precondition");
        vm.warp(vm.getBlockTimestamp() + uint256(elapsed_));
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(id, _EMERGENCY);
        vm.prank(_EMERGENCY);
        _timelock.cancelQueuedAction(id);
        ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(id);
        assertTrue(a.cancelled, "terminal cancelled");
        assertEq(a.actions.length, 0, "payload cleared");
        assertEq(_timelock.pendingActionId(_backingKey()), 0, "cancellation releases key");
        assertEq(_timelock.getQueuedConfigStateCount(id, 0), 0, "cancellation clears commitments");
        assertEq(_oracle.backing(), 100e18, "cancellation preserves backing");
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                id
            )
        );
        _timelock.executeQueuedAction(id);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-01.
    function test_givenOwnEnabled_whenEmergencyCancels() public {
        test_whenEmergencyCancels(true, true, 0);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-02.
    function test_whenUnauthorized_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != _EMERGENCY);
        uint64 id = _queue(110e18);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE));
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id);
        assertFalse(_timelock.getQueuedAction(id).cancelled, "unauthorized preserves intent");
    }

    // Scenarios: BO-CANCELQUEUEDACTION-03.
    function test_givenInactive_whenCancel_reverts(bool disabled_) public givenEnabled {
        uint64 id = _queue(110e18);
        if (disabled_) {
            vm.prank(_ADMIN);
            _timelock.disable("");
        }
        _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        _expectTimelockInactive();
        vm.prank(_EMERGENCY);
        _timelock.cancelQueuedAction(id);
        _kernel.executeAction(Actions.ActivatePolicy, address(_timelock));
        vm.prank(_EMERGENCY);
        _timelock.cancelQueuedAction(id);
        assertTrue(_timelock.getQueuedAction(id).cancelled, "cancellation after reactivation");
    }

    // Scenarios: BO-CANCELQUEUEDACTION-04.
    function test_whenAbsent_reverts(uint64 id_) public {
        _rejectMissing(id_);
    }

    // Scenarios: BO-REPLACEMENT-03.
    function test_givenOwnPaused_whenCancelWithBrokenTarget() public givenEnabled {
        uint64 id = _queue(110e18);
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.mockCallRevert(
            address(_oracle),
            bytes(""),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        vm.prank(_EMERGENCY);
        _timelock.cancelQueuedAction(id);
        assertTrue(
            _timelock.getQueuedAction(id).cancelled,
            "paused cancellation does not read target"
        );
        assertEq(_timelock.pendingActionId(_backingKey()), 0, "all keys released");
    }
}
