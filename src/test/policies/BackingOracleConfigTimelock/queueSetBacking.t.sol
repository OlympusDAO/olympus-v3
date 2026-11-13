// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Contracts
import {BackingOracleConfigTimelockTest, IBackingOracle, IEnabler, IPolicyAdmin, ITimelockBatchQueue, IConfigTimelockBatchQueue} from "./fixtures/BackingOracleConfigTimelockTest.sol";

contract BackingOracleQueueSetBackingTest is BackingOracleConfigTimelockTest {
    // Scenarios: BO-QUEUESETBACKING-11.
    function test_givenRecovered_whenQueue() public givenRecovered {
        assertEq(_queue(100e18), 1, "queue after recovery");
    }

    // Scenarios: BO-QUEUESETBACKING-12.
    function test_givenInactiveAndDisabled_whenQueue_reverts() public givenInactive {
        _expectTargetUnavailable();
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(0);
    }

    // Scenarios: BO-QUEUESETBACKING-13.
    function test_whenOne_reverts() public givenEnabled {
        _expectChange(1);
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(1);
    }

    // Scenarios: BO-QUEUESETBACKING-14.
    function test_whenTypeMaximum_reverts() public givenEnabled {
        _expectChange(type(uint256).max);
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(type(uint256).max);
    }

    // Scenarios: BO-QUEUESETBACKING-15.
    function test_whenAdjacentUpper_reverts() public givenEnabled {
        _expectChange(110e18 + 1);
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(110e18 + 1);
    }

    // Scenarios: BO-QUEUESETBACKING-16.
    function test_whenAdjacentLower_reverts() public givenEnabled {
        _expectChange(90e18 - 1);
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(90e18 - 1);
    }

    // Scenarios: BO-QUEUESETBACKING-01.
    function test_whenProposer(uint256 value_) public givenEnabled {
        value_ = bound(value_, 90e18, 110e18);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction(
            address(_oracle),
            IBackingOracle.setBacking.selector,
            abi.encode(value_)
        );
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionQueued(
            1,
            _PROPOSER,
            keccak256(abi.encode(actions)),
            uint48(vm.getBlockTimestamp() + 1 days),
            uint48(vm.getBlockTimestamp() + 8 days)
        );
        uint64 id = _queue(value_);
        ITimelockBatchQueue.QueuedAction memory a = _timelock.getQueuedAction(id);
        assertEq(id, 1, "first ID");
        assertEq(_timelock.nextActionId(), 2, "next ID");
        assertEq(a.actions[0].target, address(_oracle), "target");
        assertEq(a.actions[0].selector, IBackingOracle.setBacking.selector, "selector");
        assertEq(a.proposer, _PROPOSER, "proposer");
        assertEq(a.queuedAt, vm.getBlockTimestamp(), "queued time");
        assertEq(a.executableAt, vm.getBlockTimestamp() + 1 days, "notice");
        assertEq(a.expiresAt, vm.getBlockTimestamp() + 8 days, "window");
        assertEq(a.actions[0].payload, abi.encode(value_), "payload");
        assertFalse(a.executed || a.cancelled, "pending");
        assertEq(_oracle.backing(), 100e18, "queue does not update backing");
        assertEq(
            _timelock.getQueuedConfigDestination(id, 0),
            address(_oracle),
            "committed destination"
        );
        assertEq(_timelock.getQueuedConfigStateCount(id, 0), 1, "one backing domain");
        (bytes32 key, bytes32 stateHash) = _timelock.getQueuedConfigState(id, 0, 0);
        assertEq(key, _backingKey(), "independently encoded scoped key");
        assertEq(stateHash, _stateHash(100e18), "operator and current backing committed");
        assertEq(_timelock.pendingActionId(key), id, "reservation owner");
    }

    // Scenarios: BO-QUEUESETBACKING-02.
    function test_whenAdmin() public givenEnabled {
        vm.prank(_ADMIN);
        assertEq(_timelock.queueSetBacking(100e18), 1, "ADMIN proposal");
    }

    // Scenarios: BO-QUEUESETBACKING-03.
    function test_whenOverlappingRoles() public givenEnabled {
        _rolesAdmin.grantRole(_BACKING_ADMIN, _ADMIN);
        vm.prank(_ADMIN);
        assertEq(_timelock.queueSetBacking(100e18), 1, "overlapping roles");
    }

    // Scenarios: BO-QUEUESETBACKING-04.
    function test_whenUnauthorized_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != _ADMIN && caller_ != _PROPOSER);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _timelock.queueSetBacking(100e18);
        assertEq(_timelock.nextActionId(), 1, "failed queue preserves ID");
    }

    // Scenarios: BO-QUEUESETBACKING-05.
    function test_whenZero_reverts() public givenEnabled {
        vm.expectRevert(IBackingOracle.BackingOracle_ZeroBacking.selector);
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(0);
        assertEq(_timelock.nextActionId(), 1, "no leaked ID");
    }

    // Scenarios: BO-QUEUESETBACKING-06.
    function test_whenOutsideBounds_reverts(uint256 value_) public givenEnabled {
        value_ = bound(value_, 110e18 + 1, type(uint256).max);
        _expectChange(value_);
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(value_);
        assertEq(_timelock.nextActionId(), 1, "no leaked ID");
    }

    // Scenarios: BO-QUEUESETBACKING-07.
    function test_whenLowerOutsideBounds_reverts(uint256 value_) public givenEnabled {
        value_ = bound(value_, 1, 90e18 - 1);
        _expectChange(value_);
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(value_);
    }

    // Scenarios: BO-QUEUESETBACKING-08.
    function test_whenBoundarySeeds() public givenEnabled {
        vm.prank(_PROPOSER);
        uint64 first = _timelock.queueSetBacking(90e18);
        vm.prank(_EMERGENCY);
        _timelock.cancelQueuedAction(first);
        vm.prank(_PROPOSER);
        uint64 second = _timelock.queueSetBacking(100e18);
        vm.prank(_EMERGENCY);
        _timelock.cancelQueuedAction(second);
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(110e18);
        assertEq(_timelock.nextActionId(), 4, "sequential boundary proposals");
    }

    // Scenarios: BO-QUEUESETBACKING-09.
    function test_givenDisabled_whenQueue_reverts() public {
        _expectTargetUnavailable();
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(100e18);
    }

    // Scenarios: BO-QUEUESETBACKING-10.
    function test_givenInactive_whenQueue_reverts() public givenEnabled givenInactive {
        _expectTargetUnavailable();
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(100e18);
    }

    // Scenarios: BO-TIMELOCK-QUEUESETBACKING-03.
    function test_givenOwnInactive_whenQueue_reverts() public givenEnabled givenTimelockInactive {
        _expectTimelockInactive();
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(100e18);
    }

    // Scenarios: BO-TIMELOCK-QUEUESETBACKING-02.
    function test_givenOwnPaused_whenQueue_reverts() public givenEnabled {
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(100e18);
    }

    // Scenarios: BO-TIMELOCK-QUEUESETBACKING-01.
    function test_givenOperatorRevoked_whenQueue_reverts() public givenEnabled {
        vm.prank(_ADMIN);
        _oracle.setConfigOperator(address(0));
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(100e18);
    }

    // Scenarios: BO-REPLACEMENT-02.
    function test_givenPending_whenConflict_reverts() public givenEnabled {
        uint64 id = _queue(110e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _backingKey(),
                id
            )
        );
        vm.prank(_PROPOSER);
        _timelock.queueSetBacking(90e18);
        assertEq(_timelock.nextActionId(), 2, "failed conflict does not leak ID");
        assertEq(_timelock.pendingActionId(_backingKey()), id, "reservation remains owned");
    }
}
