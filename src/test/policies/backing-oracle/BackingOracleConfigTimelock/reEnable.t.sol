// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BackingOracleConfigTimelockTest, Actions, IPolicyAdmin, IEnabler, BackingOracleConfigTimelock, IBackingOracle} from "./fixtures/BackingOracleConfigTimelockTest.sol";

contract BackingOracleTimelockReEnableTest is BackingOracleConfigTimelockTest {
    // Scenarios: BO-TIMELOCK-REENABLE-01.
    function test_givenPending_whenRecoverPreservesIntent(bool targetEnabled_) public givenEnabled {
        uint64 id = _queue(110e18);
        uint48 ready = _timelock.getQueuedAction(id).executableAt;
        bytes32 intentHash = keccak256(abi.encode(_timelock.getQueuedAction(id)));
        if (!targetEnabled_) {
            vm.prank(_ADMIN);
            _oracle.disable("");
        }
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.prank(_PROPOSER);
        _timelock.reEnable();
        assertTrue(_timelock.isEnabled(), "queue repair permits an active paused target");
        assertEq(_timelock.pendingActionId(_backingKey()), id, "pending ownership preserved");
        assertEq(_timelock.getQueuedAction(id).executableAt, ready, "original notice retained");
        assertEq(
            keccak256(abi.encode(_timelock.getQueuedAction(id))),
            intentHash,
            "all queued metadata and payload preserved"
        );
        assertEq(_oracle.backing(), 100e18, "queue recovery does not rewrite backing");
    }

    // Scenarios: BO-TIMELOCK-REENABLE-11.
    function test_givenTargetInactive_whenRecover_reverts(bool targetEnabled_) public givenEnabled {
        uint64 id = _queue(110e18);
        if (!targetEnabled_) {
            vm.prank(_ADMIN);
            _oracle.disable("");
        }
        _kernel.executeAction(Actions.DeactivatePolicy, address(_oracle));
        vm.prank(_ADMIN);
        _timelock.disable("");
        bytes32 intent = _pendingIntentHash(id);
        uint48 previousTransition = _timelock.lastTransitionAt();
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.recordLogs();
        _expectTargetUnavailable();
        vm.prank(_PROPOSER);
        _timelock.reEnable();
        assertEq(vm.getRecordedLogs().length, 0, "inactive target rejects recovery without events");
        assertFalse(_timelock.isEnabled(), "failed recovery leaves queue paused");
        assertEq(
            _timelock.lastTransitionAt(),
            previousTransition,
            "failed recovery preserves timestamp"
        );
        assertEq(_pendingIntentHash(id), intent, "failed recovery preserves pending intent");
        _kernel.executeAction(Actions.ActivatePolicy, address(_oracle));
        vm.prank(_PROPOSER);
        _timelock.reEnable();
        assertTrue(
            _timelock.isEnabled(),
            "reactivating the target permits recovery even if paused"
        );
        assertEq(_pendingIntentHash(id), intent, "successful recovery preserves pending intent");
    }

    // Scenarios: BO-TIMELOCK-REENABLE-02.
    function test_givenOwnInactive_whenRecover_reverts() public givenTimelockInactive {
        vm.prank(_EMERGENCY);
        _timelock.disable("");
        _expectTimelockInactive();
        vm.prank(_PROPOSER);
        _timelock.reEnable();
    }

    // Scenarios: BO-TIMELOCK-REENABLE-03.
    function test_givenOperatorRevoked_whenRecover_reverts() public {
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(address(0));
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_PROPOSER);
        _timelock.reEnable();
    }

    // Scenarios: BO-TIMELOCK-REENABLE-04.
    function test_givenDisabled_whenAfterDeadline_reverts() public {
        vm.prank(_ADMIN);
        _timelock.disable("");
        uint48 deadline = uint48(vm.getBlockTimestamp() + 7 days);
        vm.warp(uint256(deadline) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(_ADMIN);
        _timelock.reEnable();
    }

    // Scenarios: BO-TIMELOCK-REENABLE-10.
    function test_givenDisabled_whenAuthorized(
        bool asAdmin_,
        bool overlap_,
        uint48 elapsed_
    ) public {
        if (overlap_) _rolesAdmin.grantRole(_BACKING_ADMIN, _ADMIN);
        elapsed_ = uint48(bound(elapsed_, 0, 7 days));
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.warp(vm.getBlockTimestamp() + elapsed_);
        vm.prank(asAdmin_ ? _ADMIN : _PROPOSER);
        _timelock.reEnable();
        assertTrue(_timelock.isEnabled(), "either authorized class recovers within grace");
    }

    // Scenarios: BO-TIMELOCK-REENABLE-09.
    function test_givenDisabled_whenAtDeadline() public {
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.warp(vm.getBlockTimestamp() + 7 days);
        vm.prank(_ADMIN);
        _timelock.reEnable();
        assertTrue(_timelock.isEnabled(), "inclusive queue grace deadline");
    }

    // Scenarios: BO-TIMELOCK-REENABLE-08.
    function test_givenEnabled_whenRecover_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(_ADMIN);
        _timelock.reEnable();
    }

    // Scenarios: BO-TIMELOCK-REENABLE-07.
    function test_givenNeverEnabled_whenRecover_reverts() public {
        BackingOracleConfigTimelock fresh = new BackingOracleConfigTimelock(
            _kernel,
            IBackingOracle(address(_oracle))
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(_ADMIN);
        fresh.reEnable();
    }

    // Scenarios: BO-TIMELOCK-REENABLE-06.
    function test_givenDisabled_whenUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != _ADMIN && caller_ != _PROPOSER);
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _timelock.reEnable();
    }

    // Scenarios: BO-TIMELOCK-REENABLE-05.
    function test_givenDeadlineOverflow_whenRecover_reverts() public {
        vm.warp(type(uint48).max);
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(type(uint48).max) + 7 days
            )
        );
        vm.prank(_ADMIN);
        _timelock.reEnable();
    }
}
