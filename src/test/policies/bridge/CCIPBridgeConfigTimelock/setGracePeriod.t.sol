// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

// Contracts
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPBridgeConfigTimelockTest} from "./CCIPBridgeConfigTimelockTest.sol";

contract CCIPBridgeConfigTimelockTests_setGracePeriod is CCIPBridgeConfigTimelockTest {
    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    // The setUp default state. The enabled gate is what keeps the window fixed after a
    // disable, so the emergency role cannot extend it during an incident.
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        timelock.setGracePeriod(5 days);
    }

    // given the timelock is disabled
    //   when the caller is not an admin
    //     [X] it reverts with NotEnabled
    // Pins the guard order: the lifecycle modifier answers before the role check
    function test_givenDisabled_whenCallerIsNotAdmin_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(thirdParty);
        timelock.setGracePeriod(5 days);
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // Fuzzed; excludes the admin account
    function test_whenCallerIsNotAdmin_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        timelock.setGracePeriod(5 days);
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The spec rationale: emergency may disable but never widen the recovery window
    function test_whenCallerIsEmergency_reverts() public givenEnabled {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(emergency);
        timelock.setGracePeriod(5 days);
    }

    // when the caller holds the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // Role asymmetry: the bridge admin consumes the window through reEnable but cannot set it
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        timelock.setGracePeriod(5 days);
    }

    // when the caller is not an admin
    //   when the period is zero
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the guard order: the role check answers before the zero-period check
    function test_whenCallerIsNotAdmin_whenPeriodIsZero_reverts() public givenEnabled {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(thirdParty);
        timelock.setGracePeriod(0);
    }

    // when the period is zero
    //   [X] it reverts with GracePeriod_ZeroPeriod
    function test_whenPeriodIsZero_reverts() public givenEnabled {
        vm.expectRevert(abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector));
        vm.prank(admin);
        timelock.setGracePeriod(0);
    }

    // when the caller is the admin
    //   [X] it writes gracePeriod
    //   [X] it emits GracePeriodSet with the new value
    function test_whenCallerIsAdmin() public givenEnabled {
        vm.expectEmit(true, true, true, true, address(timelock));
        emit IGracePeriod.GracePeriodSet(5 days);
        vm.prank(admin);
        timelock.setGracePeriod(5 days);

        assertEq(timelock.gracePeriod(), 5 days, "gracePeriod should be the new value");
    }

    // when the period equals the current value
    //   [X] it writes and emits GracePeriodSet again
    // No idempotency short-circuit exists in the base setter
    function test_whenPeriodEqualsCurrentValue() public givenEnabled {
        uint32 currentPeriod = timelock.gracePeriod();
        assertEq(currentPeriod, GRACE_PERIOD, "the current window should be the constructor value");

        vm.expectEmit(true, true, true, true, address(timelock));
        emit IGracePeriod.GracePeriodSet(currentPeriod);
        vm.prank(admin);
        timelock.setGracePeriod(currentPeriod);

        assertEq(timelock.gracePeriod(), currentPeriod, "gracePeriod should be unchanged");
    }

    // when the period is one second
    //   [X] it writes gracePeriod as one
    // The zero check is an equality, so one is the smallest accepted window
    function test_whenPeriodIsOne() public givenEnabled {
        vm.prank(admin);
        timelock.setGracePeriod(1);

        assertEq(timelock.gracePeriod(), 1, "gracePeriod should be one second");
    }

    // when the period is the uint32 maximum
    //   [X] it writes gracePeriod as type(uint32).max
    // No upper bound exists; a maximal window effectively disarms the grace expiry
    function test_whenPeriodIsMax() public givenEnabled {
        vm.prank(admin);
        timelock.setGracePeriod(type(uint32).max);

        assertEq(
            timelock.gracePeriod(),
            type(uint32).max,
            "gracePeriod should be the uint32 maximum"
        );
    }

    // when the period is any non-zero value
    //   [X] it writes gracePeriod equal to the argument
    // Fuzzed over the valid interval [1, type(uint32).max]
    function test_whenPeriodIsNonZero(uint32 period_) public givenEnabled {
        uint32 boundedPeriod = uint32(bound(period_, 1, type(uint32).max));
        // boundedPeriod is in the valid interval [1, type(uint32).max]

        vm.prank(admin);
        timelock.setGracePeriod(boundedPeriod);

        assertEq(timelock.gracePeriod(), boundedPeriod, "gracePeriod should equal the argument");
    }

    // given the timelock was re-enabled within grace
    //   [X] it writes gracePeriod
    // The enabled flag has two writers; this is the reEnable producer
    function test_givenReEnabled() public givenEnabled givenDisabled givenReEnabled {
        vm.prank(admin);
        timelock.setGracePeriod(5 days);

        assertEq(timelock.gracePeriod(), 5 days, "gracePeriod should be written");
    }

    // given the timelock is disabled after the window was changed
    //   [X] the reEnable deadline uses the new window
    // The cross-function consequence: the value written while enabled governs the next
    // disable's recovery window, observed through a reEnable at the edge of the new window
    function test_givenDisabledAfterSet() public givenEnabled {
        vm.prank(admin);
        timelock.setGracePeriod(10 days);

        vm.prank(admin);
        timelock.disable("");

        // deadline = lastTransitionAt + 10 days (the window written while enabled); the
        // constructor window of 3 days would have expired 7 days earlier
        uint48 transitionAt = timelock.lastTransitionAt();
        uint256 newDeadline = uint256(transitionAt) + 10 days;
        skip(newDeadline - vm.getBlockTimestamp());
        assertGt(
            vm.getBlockTimestamp(),
            uint256(transitionAt) + GRACE_PERIOD,
            "the timestamp should sit past the deadline of the constructor window"
        );

        vm.prank(bridgeAdmin);
        timelock.reEnable();

        assertTrue(timelock.isEnabled(), "the re-enable should succeed inside the new window");
    }

    // given the timelock policy has been deactivated in the kernel
    //   [X] it writes gracePeriod
    // The cached ROLES pointer keeps authorizing and the enabled flag persists
    function test_givenPolicyDeactivatedInKernel()
        public
        givenEnabled
        givenPolicyDeactivatedInKernel
    {
        assertFalse(timelock.isActive(), "the timelock should be deactivated in the kernel");

        vm.prank(admin);
        timelock.setGracePeriod(5 days);

        assertEq(timelock.gracePeriod(), 5 days, "gracePeriod should be written");
    }
}
