// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";

// Contracts
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {BRIDGE_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_reEnable is CCIPBridgeConfigTest {
    // given the policy is enabled
    //   [X] it reverts with NotDisabled
    function test_givenEnabled_reverts() public givenEnabled {
        _expectRevertNotDisabled();
        vm.prank(bridgeAdmin);
        config.reEnable();
    }

    // given the policy is enabled
    //   when the caller does not hold the bridge admin role
    //     [X] it reverts with NotDisabled
    // Pins the masking order: the lifecycle modifier answers before the authorization hook
    function test_givenEnabled_whenCallerIsNotBridgeAdmin_reverts() public givenEnabled {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotDisabled();
        vm.prank(caller);
        config.reEnable();
    }

    // given the policy has never been enabled
    //   [X] it reverts with NeverEnabled
    // lastTransitionAt is zero only before the first enable; the caller is the bridge admin
    function test_givenNeverEnabled_reverts() public {
        assertEq(config.lastTransitionAt(), 0, "lastTransitionAt should be zero before enable");

        vm.expectRevert(abi.encodeWithSelector(IReEnabler.NeverEnabled.selector));
        vm.prank(bridgeAdmin);
        config.reEnable();
    }

    // given the policy has never been enabled
    //   when the caller does not hold the bridge admin role
    //     [X] it reverts with NeverEnabled
    // Pins the order: the NeverEnabled check runs before the authorization hook
    function test_givenNeverEnabled_whenCallerIsNotBridgeAdmin_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        vm.expectRevert(abi.encodeWithSelector(IReEnabler.NeverEnabled.selector));
        vm.prank(caller);
        config.reEnable();
    }

    // when the caller does not hold the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // The fuzz excludes the bridge admin account and the zero address
    function test_whenCallerIsNotBridgeAdmin_reverts(
        address caller_
    ) public givenEnabled givenDisabled {
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(caller_);
        config.reEnable();
    }

    // when the caller holds only the admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Role asymmetry by design: the admin restarts the policy through enable, not reEnable
    function test_whenCallerIsAdmin_reverts() public givenEnabled givenDisabled {
        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(admin);
        config.reEnable();
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenDisabled {
        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(emergency);
        config.reEnable();
    }

    // when the caller holds only the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled givenDisabled {
        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        config.reEnable();
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with ROLES_RequireRole("bridge_admin")
    function test_whenCallerIsConfigOperator_reverts()
        public
        givenEnabled
        givenConfigOperatorSet
        givenDisabled
    {
        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(operator);
        config.reEnable();
    }

    // given the grace window has expired
    //   when the caller does not hold the bridge admin role
    //     [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Pins the order: the role check runs before the grace check, so an unauthorized caller
    // never learns whether the window is still open.
    function test_givenGraceExpired_whenCallerIsNotBridgeAdmin_reverts()
        public
        givenEnabled
        givenDisabled
        givenGraceExpired
    {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(caller);
        config.reEnable();
    }

    // given the grace window has expired
    //   [X] it reverts with GracePeriod_Expired carrying the deadline
    // The failing boundary side: the block timestamp is deadline + 1, and the error argument is
    // asserted to equal lastTransitionAt + gracePeriod.
    function test_givenGraceExpired_reverts() public givenEnabled givenDisabled givenGraceExpired {
        assertEq(
            graceDeadline,
            uint48(uint256(config.lastTransitionAt()) + config.gracePeriod()),
            "the exposed deadline should equal lastTransitionAt + gracePeriod"
        );
        assertEq(
            vm.getBlockTimestamp(),
            uint256(graceDeadline) + 1,
            "the block timestamp should sit one second past the deadline"
        );

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, graceDeadline)
        );
        vm.prank(bridgeAdmin);
        config.reEnable();
    }

    // given the block timestamp equals the grace deadline
    //   [X] it enables the policy
    // The grace check is strictly greater-than, so the deadline itself is still open
    function test_givenTimestampEqualsDeadline() public givenEnabled givenDisabled {
        uint256 deadline = uint256(config.lastTransitionAt()) + config.gracePeriod();
        skip(deadline - vm.getBlockTimestamp());
        assertEq(
            vm.getBlockTimestamp(),
            deadline,
            "the block timestamp should equal the grace deadline"
        );

        vm.prank(bridgeAdmin);
        config.reEnable();

        assertTrue(config.isEnabled(), "the policy should be enabled at the deadline");
    }

    // when the caller holds the bridge admin role
    //   [X] it sets isEnabled to true
    //   [X] it sets lastTransitionAt to the current timestamp
    //   [X] it emits Enabled
    //   [X] it emits Transition with the caller, true, an empty payload and the timestamp
    //   [X] it performs no call on the pool
    // The empty Transition payload is a base promise. The no-pool-call absence claim needs
    // vm.recordLogs.
    function test_whenCallerIsBridgeAdmin() public givenEnabled givenDisabled {
        uint48 timestamp = uint48(vm.getBlockTimestamp());

        vm.recordLogs();
        vm.expectEmit(true, true, true, true, address(config));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, true, true, address(config));
        emit IEnablerV2.Transition(bridgeAdmin, true, "", timestamp);
        vm.prank(bridgeAdmin);
        config.reEnable();

        assertTrue(config.isEnabled(), "the policy should be enabled");
        assertEq(
            config.lastTransitionAt(),
            timestamp,
            "lastTransitionAt should be the reEnable timestamp"
        );

        // The pool emits nothing: reEnable restores only the policy flag
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            _countLogsFrom(logs, address(pool)),
            0,
            "the pool should emit nothing during reEnable"
        );
    }

    // given the policy was re-enabled and then disabled again
    //   [X] it enables the policy at a time beyond the first window
    // The grace window restarts on every transition: the second disable opens a fresh full
    // window even after the first one would have expired.
    function test_givenDisabledAgainAfterReEnable()
        public
        givenEnabled
        givenDisabled
        givenReEnabled
    {
        // The first disable happened at T0, so its window would close at T0 + GRACE_PERIOD.
        // Move one second past that boundary, disable again and use the fresh window.
        uint256 firstDeadline = uint256(config.lastTransitionAt()) + config.gracePeriod();
        skip(firstDeadline + 1 - vm.getBlockTimestamp());

        vm.prank(admin);
        config.disable("");

        // The second window measures from the second disable: its deadline is
        // (T0 + GRACE_PERIOD + 1) + GRACE_PERIOD, so the full window is open again.
        uint256 secondDeadline = uint256(config.lastTransitionAt()) + config.gracePeriod();
        skip(secondDeadline - vm.getBlockTimestamp());
        assertGt(
            vm.getBlockTimestamp(),
            firstDeadline,
            "the reEnable time should sit beyond the first window"
        );

        vm.prank(bridgeAdmin);
        config.reEnable();

        assertTrue(config.isEnabled(), "the policy should be enabled in the restarted window");
    }

    // given the policy was re-enabled
    //   [X] it reverts with NotDisabled
    // The repeat call after a successful reEnable; the enabled flag has two writers and this
    // pins the reEnable-written one.
    function test_givenReEnabled_reverts() public givenEnabled givenDisabled givenReEnabled {
        _expectRevertNotDisabled();
        vm.prank(bridgeAdmin);
        config.reEnable();
    }
}
