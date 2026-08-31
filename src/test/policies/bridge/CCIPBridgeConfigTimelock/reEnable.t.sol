// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPBridgeConfigTimelock} from "src/policies/interfaces/bridge/ICCIPBridgeConfigTimelock.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BRIDGE_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPBridgeConfigTimelockTest} from "./CCIPBridgeConfigTimelockTest.sol";

contract CCIPBridgeConfigTimelockTests_reEnable is CCIPBridgeConfigTimelockTest {
    // given the timelock is enabled
    //   [X] it reverts with NotDisabled
    function test_givenEnabled_reverts() public givenEnabled {
        _expectRevertNotDisabled();
        vm.prank(bridgeAdmin);
        timelock.reEnable();
    }

    // given the timelock has never been enabled
    //   [X] it reverts with NeverEnabled
    // The setUp default state; the caller is the bridge admin, so even the authorized caller
    // cannot re-enable a never-enabled timelock
    function test_givenNeverEnabled_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IReEnabler.NeverEnabled.selector));
        vm.prank(bridgeAdmin);
        timelock.reEnable();
    }

    // given the timelock has never been enabled
    //   when the caller is not a bridge admin
    //     [X] it reverts with NeverEnabled
    // Pins the guard order: the never-enabled check answers before the role check
    function test_givenNeverEnabled_whenCallerIsNotBridgeAdmin_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IReEnabler.NeverEnabled.selector));
        vm.prank(thirdParty);
        timelock.reEnable();
    }

    // when the caller does not hold the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Fuzzed; excludes the bridge admin account
    function test_whenCallerIsNotBridgeAdmin_reverts(
        address caller_
    ) public givenEnabled givenDisabled {
        vm.assume(caller_ != bridgeAdmin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(caller_);
        timelock.reEnable();
    }

    // when the caller holds the admin role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // The admin is deliberately rejected: it restarts the policy through enable, which is not
    // grace-gated
    function test_whenCallerIsAdmin_reverts() public givenEnabled givenDisabled {
        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(admin);
        timelock.reEnable();
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // Role asymmetry: emergency may disable but never restore
    function test_whenCallerIsEmergency_reverts() public givenEnabled givenDisabled {
        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(emergency);
        timelock.reEnable();
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("bridge_admin")
    // The bridge rate limiter holds no timelock authority at all
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled givenDisabled {
        _expectRevertRequireRole(BRIDGE_ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        timelock.reEnable();
    }

    // given the grace window since the last disable has expired
    //   [X] it reverts with GracePeriod_Expired carrying the deadline
    // givenGraceExpired lands exactly at deadline + 1, the first failing second of the strict
    // comparison; the error argument is asserted against graceDeadline
    function test_givenGraceExpired_reverts() public givenEnabled givenDisabled givenGraceExpired {
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, graceDeadline)
        );
        vm.prank(bridgeAdmin);
        timelock.reEnable();
    }

    // given the grace window has expired
    //   given the config policy has been deactivated in the kernel
    //     [X] it reverts with GracePeriod_Expired
    // Pins the hook order: super._beforeReEnable() runs the grace check before the
    // config-activity check
    function test_givenGraceExpired_givenConfigDeactivatedInKernel_reverts()
        public
        givenEnabled
        givenDisabled
        givenGraceExpired
        givenConfigDeactivatedInKernel
    {
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, graceDeadline)
        );
        vm.prank(bridgeAdmin);
        timelock.reEnable();
    }

    // given the config policy has been deactivated in the kernel
    //   [X] it reverts with CCIPBridgeConfigTimelock_ConfigNotActive carrying the config
    //       address
    // Within the grace window, so the config-activity check is the deciding guard
    function test_givenConfigDeactivatedInKernel_reverts()
        public
        givenEnabled
        givenDisabled
        givenConfigDeactivatedInKernel
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPBridgeConfigTimelock.CCIPBridgeConfigTimelock_ConfigNotActive.selector,
                address(config)
            )
        );
        vm.prank(bridgeAdmin);
        timelock.reEnable();
    }

    // when the caller is the bridge admin
    //   [X] it sets isEnabled true
    //   [X] it sets lastTransitionAt to the current timestamp
    //   [X] it emits Enabled
    //   [X] it emits Transition with the caller, true, an empty payload and the timestamp
    function test_whenCallerIsBridgeAdmin() public givenEnabled givenDisabled {
        // A time skip separates the re-enable timestamp from the disable timestamp
        skip(1 hours);
        uint48 timestamp = uint48(vm.getBlockTimestamp());

        vm.expectEmit(true, true, true, true, address(timelock));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, true, true, address(timelock));
        emit IEnablerV2.Transition(bridgeAdmin, true, "", timestamp);
        vm.prank(bridgeAdmin);
        timelock.reEnable();

        assertTrue(timelock.isEnabled(), "the timelock should be enabled");
        assertEq(
            timelock.lastTransitionAt(),
            timestamp,
            "lastTransitionAt should be the re-enable timestamp"
        );
    }

    // given the block timestamp equals the grace deadline
    //   [X] it re-enables
    // The grace comparison is strict, so the deadline itself is still open
    function test_givenTimestampEqualsGraceDeadline()
        public
        givenEnabled
        givenDisabled
        givenTimestampAtGraceDeadline
    {
        assertEq(
            vm.getBlockTimestamp(),
            uint256(timelock.lastTransitionAt()) + timelock.gracePeriod(),
            "the block timestamp should sit exactly on the grace deadline"
        );

        vm.prank(bridgeAdmin);
        timelock.reEnable();

        assertTrue(timelock.isEnabled(), "the timelock should be enabled at the deadline");
    }

    // given the timelock was disabled by the emergency role
    //   [X] it re-enables
    // The second producer of the disabled state; the incident flow is emergency disables,
    // bridge admin recovers
    function test_givenDisabledByEmergency() public givenEnabled givenDisabledByEmergency {
        vm.prank(bridgeAdmin);
        timelock.reEnable();

        assertTrue(timelock.isEnabled(), "the timelock should be enabled after the incident flow");
    }

    // given the timelock was re-enabled and then disabled again
    //   [X] it re-enables within the fresh window
    // The grace window restarts on every transition, so the second disable opens a new
    // full-length window
    function test_givenSecondDisableAfterReEnable()
        public
        givenEnabled
        givenDisabled
        givenReEnabled
        givenDisabled
    {
        // givenReEnabled skipped one day between the two disables, so the fresh deadline
        // (second disable + grace) sits one day past the first window's deadline (first
        // disable + grace). Landing on the fresh deadline is therefore strictly past the
        // first window, and only the restart makes the re-enable succeed.
        uint48 secondDisableAt = timelock.lastTransitionAt();
        uint256 freshDeadline = uint256(secondDisableAt) + timelock.gracePeriod();
        uint256 firstWindowDeadline = uint256(secondDisableAt) - 1 days + timelock.gracePeriod();
        skip(freshDeadline - vm.getBlockTimestamp());
        assertGt(
            vm.getBlockTimestamp(),
            firstWindowDeadline,
            "the fresh deadline should sit past the first window's deadline"
        );

        vm.prank(bridgeAdmin);
        timelock.reEnable();

        assertTrue(timelock.isEnabled(), "the timelock should be enabled in the fresh window");
    }

    // given the config policy is disabled but still active in the kernel
    //   [X] it re-enables
    // Like enable, the hook checks kernel activity only, never enablement
    function test_givenConfigDisabled() public givenEnabled givenDisabled givenConfigDisabled {
        assertFalse(config.isEnabled(), "the config policy should be disabled");

        vm.prank(bridgeAdmin);
        timelock.reEnable();

        assertTrue(timelock.isEnabled(), "the timelock should re-enable over a disabled config");
    }

    // given the config policy was deactivated and then re-activated in the kernel
    //   [X] it re-enables
    // The unblock path of the ConfigNotActive gate
    function test_givenConfigReactivatedInKernel() public givenEnabled givenDisabled {
        kernel.executeAction(Actions.DeactivatePolicy, address(config));
        kernel.executeAction(Actions.ActivatePolicy, address(config));

        vm.prank(bridgeAdmin);
        timelock.reEnable();

        assertTrue(timelock.isEnabled(), "the timelock should re-enable after the re-activation");
    }

    // given the timelock policy has been deactivated in the kernel
    //   [X] it re-enables
    // The hook checks the config's activity, never the timelock's own
    function test_givenPolicyDeactivatedInKernel()
        public
        givenEnabled
        givenDisabled
        givenPolicyDeactivatedInKernel
    {
        assertFalse(timelock.isActive(), "the timelock should be deactivated in the kernel");

        vm.prank(bridgeAdmin);
        timelock.reEnable();

        assertTrue(timelock.isEnabled(), "the timelock should re-enable while deactivated");
    }
}
