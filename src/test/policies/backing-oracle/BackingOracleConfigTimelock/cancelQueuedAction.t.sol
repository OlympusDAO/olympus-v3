// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Contracts
import {BackingOracleConfigTimelockTest, ITimelockBatchQueue, IConfigTimelockBatchQueue, IPolicyAdmin} from "./fixtures/BackingOracleConfigTimelockTest.sol";
import {Actions} from "src/Kernel.sol";

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

    function _pause() private {
        vm.prank(_ADMIN);
        _timelock.disable("");
    }

    /// @dev Reads only the queue, so it also serves cases whose oracle calls all revert.
    function _cancel(address caller_, uint64 id_) private {
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(id_, caller_);
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id_);
        ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(id_);
        assertTrue(a.cancelled, "terminal cancelled");
        assertEq(a.actions.length, 0, "payload cleared");
        assertEq(_timelock.pendingActionId(_backingKey()), 0, "cancellation releases key");
        assertEq(_timelock.getQueuedConfigStateCount(id_, 0), 0, "cancellation clears commitments");
    }

    function _rejectInactiveThenCancel(address caller_, uint48 elapsed_) private {
        uint64 id = _queue(110e18);
        skip(elapsed_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        _expectTimelockInactive();
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id);
        assertFalse(_timelock.getQueuedAction(id).cancelled, "inactive preserves intent");
        _kernel.executeAction(Actions.ActivatePolicy, address(_timelock));
        _cancel(caller_, id);
    }

    function _cancelWithBrokenTarget(address caller_, uint48 elapsed_) private {
        uint64 id = _queue(110e18);
        _pause();
        skip(elapsed_);
        vm.mockCallRevert(
            address(_oracle),
            bytes(""),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        // Counts every oracle call until the end of the test.
        vm.expectCall(address(_oracle), bytes(""), 0);
        _cancel(caller_, id);
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
    function test_whenUnauthorized_reverts(address caller_, uint48 elapsed_) public givenEnabled {
        vm.assume(caller_ != _ADMIN && caller_ != _EMERGENCY && caller_ != _PROPOSER);
        uint64 id = _queue(110e18);
        // Unexpired through X = queuedAt + 1 days + 7 days, inclusive.
        skip(bound(elapsed_, 0, 8 days));
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id);
        assertFalse(_timelock.getQueuedAction(id).cancelled, "unauthorized preserves intent");
        assertEq(_timelock.pendingActionId(_backingKey()), id, "unauthorized preserves key");
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

    // Scenarios: BO-CANCELQUEUEDACTION-06.
    function test_whenUnauthorizedAtExpiry_reverts() public givenEnabled {
        address caller = makeAddr("unrelated");
        uint64 id = _queue(110e18);
        skip(8 days);
        assertEq(vm.getBlockTimestamp(), _timelock.getQueuedAction(id).expiresAt, "exact expiry");
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller);
        _timelock.cancelQueuedAction(id);
        assertEq(_timelock.pendingActionId(_backingKey()), id, "key retained at expiry");
        vm.prank(caller);
        _timelock.executeQueuedAction(id);
        assertEq(_oracle.backing(), 110e18, "execution still open at expiry");
    }

    // Scenarios: BO-CANCELQUEUEDACTION-07.
    function test_whenOtherBackingAdmin_reverts() public givenEnabled {
        address other = makeAddr("otherBackingAdmin");
        _rolesAdmin.grantRole(_BACKING_ADMIN, other);
        uint64 id = _queue(110e18);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(other);
        _timelock.cancelQueuedAction(id);
        assertFalse(
            _timelock.getQueuedAction(id).cancelled,
            "role does not reach another proposal"
        );
    }

    // Scenarios: BO-CANCELQUEUEDACTION-08.
    function test_givenAdminProposal_whenBackingAdmin_reverts() public givenEnabled {
        vm.prank(_ADMIN);
        uint64 id = _timelock.queueSetBacking(110e18);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_PROPOSER);
        _timelock.cancelQueuedAction(id);
        ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(id);
        assertEq(a.proposer, _ADMIN, "ADMIN is the proposer");
        assertFalse(a.cancelled, "backing_admin does not cancel an ADMIN proposal");
    }

    // Scenarios: BO-CANCELQUEUEDACTION-09.
    function test_whenProposerCancels(bool queueEnabled_, uint48 elapsed_) public givenEnabled {
        uint64 id = _queue(110e18);
        if (!queueEnabled_) _pause();
        assertEq(_timelock.isEnabled(), queueEnabled_, "independent queue enablement precondition");
        // Notice and execution window through X = queuedAt + 1 days + 7 days, inclusive.
        skip(bound(elapsed_, 0, 8 days));
        _cancel(_PROPOSER, id);
        assertEq(_oracle.backing(), 100e18, "cancellation preserves backing");
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                id
            )
        );
        _timelock.executeQueuedAction(id);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-09.
    function test_whenProposerCancelsDuringNotice() public {
        test_whenProposerCancels(true, 0);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-09.
    function test_whenProposerCancelsInWindow() public {
        test_whenProposerCancels(true, 1 days);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-09.
    function test_givenOwnPaused_whenProposerCancels() public {
        test_whenProposerCancels(false, 1 days);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-10.
    function test_givenProposerLostRole_whenProposerCancels() public givenEnabled {
        uint64 id = _queue(110e18);
        _rolesAdmin.revokeRole(_BACKING_ADMIN, _PROPOSER);
        assertFalse(_roles.hasRole(_PROPOSER, _BACKING_ADMIN), "role revoked precondition");
        _cancel(_PROPOSER, id);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-11.
    function test_whenAdminCancels(bool queueEnabled_, uint48 elapsed_) public givenEnabled {
        uint64 id = _queue(110e18);
        if (!queueEnabled_) _pause();
        assertEq(_timelock.isEnabled(), queueEnabled_, "independent queue enablement precondition");
        // Notice and execution window through X = queuedAt + 1 days + 7 days, inclusive.
        skip(bound(elapsed_, 0, 8 days));
        _cancel(_ADMIN, id);
        assertEq(_timelock.getQueuedAction(id).proposer, _PROPOSER, "ADMIN is not the proposer");
    }

    // Scenarios: BO-CANCELQUEUEDACTION-11.
    function test_givenOwnEnabled_whenAdminCancels() public {
        test_whenAdminCancels(true, 0);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-11.
    function test_givenOwnPaused_whenAdminCancels() public {
        test_whenAdminCancels(false, 0);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-12.
    function test_givenExpired_whenAnyCallerCancels(
        address caller_,
        bool queueEnabled_,
        uint48 elapsed_
    ) public givenEnabled {
        uint64 id = _queue(110e18);
        if (!queueEnabled_) _pause();
        // Strictly after X = queuedAt + 8 days; the upper bound keeps the timestamp in uint48.
        skip(bound(elapsed_, 8 days + 1, type(uint48).max - vm.getBlockTimestamp()));
        _cancel(caller_, id);
        assertEq(_oracle.backing(), 100e18, "cancellation preserves backing");
    }

    // Scenarios: BO-CANCELQUEUEDACTION-12.
    function test_givenExpired_givenOwnPaused_whenUnrelatedCancels() public {
        test_givenExpired_whenAnyCallerCancels(makeAddr("unrelated"), false, 8 days + 1);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-13.
    function test_givenExpired_whenUnrelatedCancelsOneSecondAfterExpiry() public givenEnabled {
        address caller = makeAddr("unrelated");
        uint64 id = _queue(110e18);
        uint48 expiry = _timelock.getQueuedAction(id).expiresAt;
        skip(8 days + 1);
        assertEq(vm.getBlockTimestamp(), uint256(expiry) + 1, "one second after expiry");
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                id,
                expiry
            )
        );
        _timelock.executeQueuedAction(id);
        _cancel(caller, id);
        assertEq(_queue(110e18), id + 1, "released key accepts a fresh proposal");
    }

    // Scenarios: BO-CANCELQUEUEDACTION-14.
    function test_givenInactive_whenAnyCallerCancels_reverts(
        address caller_,
        bool disabled_,
        uint48 elapsed_
    ) public givenEnabled {
        uint64 id = _queue(110e18);
        if (disabled_) _pause();
        // Notice, window and expired time; the upper bound keeps the timestamp in uint48.
        skip(bound(elapsed_, 0, type(uint48).max - vm.getBlockTimestamp()));
        _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        _expectTimelockInactive();
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id);
        assertFalse(_timelock.getQueuedAction(id).cancelled, "inactive preserves intent");
        assertEq(_timelock.pendingActionId(_backingKey()), id, "inactive preserves key");
    }

    // Scenarios: BO-CANCELQUEUEDACTION-15.
    function test_givenInactive_whenProposerCancels_reverts() public givenEnabled {
        _rejectInactiveThenCancel(_PROPOSER, 0);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-15.
    function test_givenInactive_whenAdminCancels_reverts() public givenEnabled {
        _rejectInactiveThenCancel(_ADMIN, 0);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-15.
    function test_givenInactive_givenExpired_whenUnrelatedCancels_reverts() public givenEnabled {
        _rejectInactiveThenCancel(makeAddr("unrelated"), 8 days + 1);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-16.
    function test_givenInactive_whenUnauthorized_reverts() public givenEnabled {
        address caller = makeAddr("unrelated");
        uint64 id = _queue(110e18);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_timelock));
        _expectTimelockInactive();
        vm.prank(caller);
        _timelock.cancelQueuedAction(id);
        _kernel.executeAction(Actions.ActivatePolicy, address(_timelock));
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller);
        _timelock.cancelQueuedAction(id);
        assertFalse(_timelock.getQueuedAction(id).cancelled, "unauthorized preserves intent");
    }

    // Scenarios: BO-REPLACEMENT-04.
    function test_givenOwnPaused_whenProposerCancelsWithBrokenTarget() public givenEnabled {
        _cancelWithBrokenTarget(_PROPOSER, 0);
    }

    // Scenarios: BO-REPLACEMENT-05.
    function test_givenOwnPaused_givenExpired_whenUnrelatedCancelsWithBrokenTarget()
        public
        givenEnabled
    {
        _cancelWithBrokenTarget(makeAddr("unrelated"), 8 days + 1);
    }

    // Scenarios: BO-CANCELQUEUEDACTION-17.
    function test_givenBackingDrift_whenProposerCancelsAndRequeues() public givenEnabled {
        uint64 id = _queue(110e18);
        vm.prank(_ADMIN);
        _oracle.setBacking(105e18);
        skip(1 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                id,
                uint256(0),
                _backingKey(),
                _stateHash(100e18),
                _stateHash(105e18)
            )
        );
        _timelock.executeQueuedAction(id);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _backingKey(),
                id
            )
        );
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(110e18);
        _cancel(_PROPOSER, id);
        // Backing is 105e18 (18 decimals). Bounds, both rounded down:
        // 105e18 * 9_000 / 10_000 = 94.5e18 and 105e18 * 11_000 / 10_000 = 115.5e18.
        // 110e18 lies inside [94.5e18, 115.5e18].
        uint64 next = _queue(110e18);
        assertEq(next, id + 1, "fresh proposal after cancellation");
        assertEq(_timelock.pendingActionId(_backingKey()), next, "fresh proposal owns the key");
        (, bytes32 stateHash) = _timelock.getQueuedConfigState(next, 0, 0);
        assertEq(stateHash, _stateHash(105e18), "fresh proposal commits the drifted backing");
        skip(1 days);
        _timelock.executeQueuedAction(next);
        assertEq(_oracle.backing(), 110e18, "fresh proposal executes");
    }
}
