// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPTokenPoolConfigTimelockTest} from "./CCIPTokenPoolConfigTimelockTest.sol";

contract CCIPTokenPoolConfigTimelockTests_setTimelockDelay is CCIPTokenPoolConfigTimelockTest {
    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    // The setUp default state; while disabled the delay is frozen
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        timelock.setTimelockDelay(2 days);
    }

    // given the timelock is disabled
    //   when the caller is not an admin
    //     [X] it reverts with NotEnabled
    // Pins the modifier order: the lifecycle gate answers before the role gate
    function test_givenDisabled_whenCallerIsNotAdmin_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(thirdParty);
        timelock.setTimelockDelay(2 days);
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // Fuzzed; excludes the admin account
    function test_whenCallerIsNotAdmin_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        timelock.setTimelockDelay(2 days);
    }

    // when the caller holds the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The proposer role cannot change the delay its own actions queue under
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        timelock.setTimelockDelay(2 days);
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(emergency);
        timelock.setTimelockDelay(2 days);
    }

    // when the caller is not an admin
    //   when the delay is below the minimum
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the guard order: the role gate answers before the bounds check
    function test_whenCallerIsNotAdmin_whenDelayIsBelowMinimum_reverts() public givenEnabled {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(thirdParty);
        timelock.setTimelockDelay(1 days - 1);
    }

    // when the delay is one second below the minimum
    //   [X] it reverts with ITimelockBatchQueue_TimelockDelayInvalid carrying the delay and
    //       both bounds
    // The lower comparison is strict, so 1 days - 1 is the failing side of the boundary
    function test_whenDelayIsBelowMinimum_reverts() public givenEnabled {
        _expectRevertTimelockDelayInvalid(1 days - 1);
        vm.prank(admin);
        timelock.setTimelockDelay(1 days - 1);
    }

    // when the delay is one second above the maximum
    //   [X] it reverts with ITimelockBatchQueue_TimelockDelayInvalid
    // The upper comparison is strict, so 30 days + 1 is the failing side of the boundary
    function test_whenDelayIsAboveMaximum_reverts() public givenEnabled {
        _expectRevertTimelockDelayInvalid(30 days + 1);
        vm.prank(admin);
        timelock.setTimelockDelay(30 days + 1);
    }

    // when the delay is the uint48 maximum
    //   [X] it reverts with ITimelockBatchQueue_TimelockDelayInvalid
    // The maximum representable value case for the numeric input
    function test_whenDelayIsUint48Max_reverts() public givenEnabled {
        _expectRevertTimelockDelayInvalid(type(uint48).max);
        vm.prank(admin);
        timelock.setTimelockDelay(type(uint48).max);
    }

    // when the caller is the admin
    //   [X] it writes timelockDelay
    //   [X] it emits TimelockDelaySet with the new value
    function test_whenCallerIsAdmin() public givenEnabled {
        vm.expectEmit(true, true, true, true, address(timelock));
        emit ITimelockBatchQueue.TimelockDelaySet(2 days);
        vm.prank(admin);
        timelock.setTimelockDelay(2 days);

        assertEq(timelock.timelockDelay(), 2 days, "timelockDelay should be the new value");
    }

    // when the delay equals the minimum
    //   [X] it writes timelockDelay as 1 days
    // The lower comparison is strict, so the bound itself is accepted
    function test_whenDelayIsMinimum() public givenEnabled {
        vm.prank(admin);
        timelock.setTimelockDelay(1 days);

        assertEq(timelock.timelockDelay(), 1 days, "timelockDelay should be the minimum");
    }

    // when the delay equals the maximum
    //   [X] it writes timelockDelay as 30 days
    // The upper comparison is strict, so the bound itself is accepted
    function test_whenDelayIsMaximum() public givenEnabled {
        vm.prank(admin);
        timelock.setTimelockDelay(30 days);

        assertEq(timelock.timelockDelay(), 30 days, "timelockDelay should be the maximum");
    }

    // when the delay equals the current value
    //   [X] it writes and emits TimelockDelaySet again
    // No idempotency short-circuit exists in the base setter
    function test_whenDelayEqualsCurrentValue() public givenEnabled {
        uint48 currentDelay = timelock.timelockDelay();

        vm.expectEmit(true, true, true, true, address(timelock));
        emit ITimelockBatchQueue.TimelockDelaySet(currentDelay);
        vm.prank(admin);
        timelock.setTimelockDelay(currentDelay);

        assertEq(timelock.timelockDelay(), currentDelay, "timelockDelay should be unchanged");
    }

    // when the delay is any value within the bounds
    //   [X] it writes timelockDelay equal to the argument
    // Fuzzed over the valid interval [1 days, 30 days]
    function test_whenDelayIsWithinBounds(uint48 delay_) public givenEnabled {
        uint48 boundedDelay = uint48(bound(delay_, 1 days, 30 days));
        // boundedDelay is in the valid interval [1 days, 30 days]

        vm.prank(admin);
        timelock.setTimelockDelay(boundedDelay);

        assertEq(timelock.timelockDelay(), boundedDelay, "timelockDelay should equal the argument");
    }

    // given an action is queued
    //   [X] the stored executableAt and expiresAt of the queued action are unchanged by the
    //       delay change
    //   [X] an action queued after the change uses the new delay for its executableAt
    // The stored timestamps are absolute; the body queues a second action after the change
    // and compares both actions' stored fields side by side
    function test_givenActionQueued() public givenEnabled givenChainAdded givenActionQueued {
        ITimelockBatchQueue.QueuedAction memory storedBefore = timelock.getQueuedAction(
            queuedActionId
        );

        vm.prank(admin);
        timelock.setTimelockDelay(2 days);

        ITimelockBatchQueue.QueuedAction memory storedAfter = timelock.getQueuedAction(
            queuedActionId
        );
        assertEq(
            storedAfter.executableAt,
            storedBefore.executableAt,
            "the stored executableAt should not move with the delay change"
        );
        assertEq(
            storedAfter.expiresAt,
            storedBefore.expiresAt,
            "the stored expiresAt should not move with the delay change"
        );

        // The second action targets a fresh selector, so its keys cannot conflict with the
        // canonical action's route A reservation
        uint64 secondActionId = _queueAddChainAction(CHAIN_SELECTOR_B);
        ITimelockBatchQueue.QueuedAction memory secondAction = timelock.getQueuedAction(
            secondActionId
        );
        // executableAt = now + 2 days (the new delay); expiresAt = executableAt + 3 days
        assertEq(
            secondAction.executableAt,
            uint48(vm.getBlockTimestamp()) + 2 days,
            "the second action should use the new delay"
        );
        assertEq(
            secondAction.expiresAt,
            secondAction.executableAt + 3 days,
            "the second action should keep the constant execution window"
        );
    }

    // given the timelock was re-enabled within grace
    //   [X] it writes timelockDelay
    // The enabled flag has two writers; this is the reEnable producer
    function test_givenReEnabled() public givenEnabled givenDisabled givenReEnabled {
        vm.prank(admin);
        timelock.setTimelockDelay(2 days);

        assertEq(timelock.timelockDelay(), 2 days, "timelockDelay should be written");
    }

    // given the timelock policy has been deactivated in the kernel
    //   [X] it writes timelockDelay
    // The cached ROLES pointer keeps authorizing and the enabled flag persists
    function test_givenPolicyDeactivatedInKernel()
        public
        givenEnabled
        givenPolicyDeactivatedInKernel
    {
        assertFalse(timelock.isActive(), "the timelock should be deactivated in the kernel");

        vm.prank(admin);
        timelock.setTimelockDelay(2 days);

        assertEq(timelock.timelockDelay(), 2 days, "timelockDelay should be written");
    }
}
