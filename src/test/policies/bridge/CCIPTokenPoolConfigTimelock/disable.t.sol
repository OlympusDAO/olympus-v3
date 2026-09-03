// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {CCIPTokenPoolConfigTimelockTest} from "./CCIPTokenPoolConfigTimelockTest.sol";

contract CCIPTokenPoolConfigTimelockTests_disable is CCIPTokenPoolConfigTimelockTest {
    // given the timelock is disabled
    //   [X] it reverts with NotEnabled
    // The fresh never-enabled state after setUp
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        timelock.disable("");
    }

    // given the timelock is disabled
    //   when the caller is not authorized
    //     [X] it reverts with NotEnabled
    // Pins the guard order: the lifecycle modifier answers before the role check
    function test_givenDisabled_whenCallerIsNotAuthorized_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(thirdParty);
        timelock.disable("");
    }

    // when the caller holds neither the emergency nor the admin role
    //   [X] it reverts with NotAuthorised
    // Fuzzed; excludes the admin and emergency accounts. The composite modifier reports
    // NotAuthorised, not ROLES_RequireRole.
    function test_whenCallerIsNotAuthorized_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != emergency);
        vm.assume(caller_ != address(0));

        _expectRevertNotAuthorised();
        vm.prank(caller_);
        timelock.disable("");
    }

    // when the caller holds the bridge admin role
    //   [X] it reverts with NotAuthorised
    // Role asymmetry: the bridge admin may reEnable within grace but may not disable
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled {
        _expectRevertNotAuthorised();
        vm.prank(bridgeAdmin);
        timelock.disable("");
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with NotAuthorised
    // The bridge rate limiter holds no timelock authority at all
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled {
        _expectRevertNotAuthorised();
        vm.prank(bridgeRateLimiter);
        timelock.disable("");
    }

    // when the caller is the admin
    //   [X] it sets isEnabled false
    //   [X] it sets lastTransitionAt to the current timestamp
    //   [X] it emits Disabled
    //   [X] it emits Transition with the caller, false, the payload and the timestamp
    // The lastTransitionAt write is the reference point the reEnable grace window measures
    // from
    function test_whenCallerIsAdmin() public givenEnabled {
        skip(1 hours);
        uint48 timestamp = uint48(vm.getBlockTimestamp());

        vm.expectEmit(true, true, true, true, address(timelock));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, true, true, address(timelock));
        emit IEnablerV2.Transition(admin, false, "", timestamp);
        vm.prank(admin);
        timelock.disable("");

        assertFalse(timelock.isEnabled(), "the timelock should be disabled");
        assertEq(
            timelock.lastTransitionAt(),
            timestamp,
            "lastTransitionAt should be the disable timestamp"
        );
    }

    // when the caller holds the emergency role
    //   [X] it disables
    // The second authorized class gets its own success case
    function test_whenCallerIsEmergency() public givenEnabled {
        vm.prank(emergency);
        timelock.disable("");

        assertFalse(timelock.isEnabled(), "the timelock should be disabled by the emergency role");
    }

    // when the payload is not empty
    //   [X] it disables and carries the payload verbatim in the Transition event
    // The payload is never decoded; fuzzed over arbitrary bytes
    function test_whenDataIsNotEmpty(bytes calldata data_) public givenEnabled {
        vm.assume(data_.length > 0);
        uint48 timestamp = uint48(vm.getBlockTimestamp());

        vm.expectEmit(true, true, true, true, address(timelock));
        emit IEnablerV2.Transition(admin, false, data_, timestamp);
        vm.prank(admin);
        timelock.disable(data_);

        assertFalse(timelock.isEnabled(), "the timelock should be disabled");
    }

    // given the timelock was re-enabled within grace
    //   [X] it disables again
    // The enabled flag has two writers (enable and reEnable); this is the reEnable producer
    function test_givenReEnabled() public givenEnabled givenDisabled givenReEnabled {
        uint48 timestamp = uint48(vm.getBlockTimestamp());

        vm.prank(admin);
        timelock.disable("");

        assertFalse(timelock.isEnabled(), "the timelock should be disabled after the re-enable");
        assertEq(
            timelock.lastTransitionAt(),
            timestamp,
            "lastTransitionAt should be the second disable timestamp"
        );
    }

    // given an action is queued
    //   [X] it disables
    //   [X] the stored action keeps its proposer, queuedAt, executableAt and expiresAt
    //   [X] pendingActionId still names the action for its reserved key
    //   [X] the stored config state count is unchanged
    // Disable performs no queue bookkeeping: the timestamps are absolute, so the delay keeps
    // running while disabled (the executable-after-re-enable consequence lands in the execute
    // pass)
    function test_givenActionQueued() public givenEnabled givenChainAdded givenActionQueued {
        ITimelockBatchQueue.QueuedAction memory storedBefore = timelock.getQueuedAction(
            queuedActionId
        );
        // The canonical action is a rate limit change, so it reserves the rate limits key of
        // route A alone
        bytes32 rateLimitsKey = timelock.getRateLimitsKey(CHAIN_SELECTOR_A);

        vm.prank(admin);
        timelock.disable("");

        assertFalse(timelock.isEnabled(), "the timelock should be disabled");

        ITimelockBatchQueue.QueuedAction memory storedAfter = timelock.getQueuedAction(
            queuedActionId
        );
        assertEq(
            storedAfter.proposer,
            storedBefore.proposer,
            "the stored proposer should survive the disable"
        );
        assertEq(
            storedAfter.queuedAt,
            storedBefore.queuedAt,
            "the stored queuedAt should survive the disable"
        );
        assertEq(
            storedAfter.executableAt,
            storedBefore.executableAt,
            "the stored executableAt should survive the disable"
        );
        assertEq(
            storedAfter.expiresAt,
            storedBefore.expiresAt,
            "the stored expiresAt should survive the disable"
        );
        assertFalse(storedAfter.executed, "the action should not be marked executed");
        assertFalse(storedAfter.cancelled, "the action should not be marked cancelled");

        assertEq(
            timelock.pendingActionId(rateLimitsKey),
            queuedActionId,
            "the reserved rate limits key should still name the action"
        );
        assertEq(
            timelock.getQueuedConfigStateCount(queuedActionId, 0),
            1,
            "the stored config state count should be unchanged"
        );
    }

    // given the config policy has been deactivated in the kernel
    //   [X] it disables
    // Unlike enable, disable has no config hook: containment stays reachable over a broken
    // binding
    function test_givenConfigDeactivatedInKernel()
        public
        givenEnabled
        givenConfigDeactivatedInKernel
    {
        assertFalse(config.isActive(), "the config policy should be deactivated in the kernel");

        vm.prank(admin);
        timelock.disable("");

        assertFalse(timelock.isEnabled(), "the timelock should be disabled over a broken binding");
    }

    // given the timelock policy has been deactivated in the kernel
    //   [X] it disables
    // The cached ROLES pointer keeps authorizing after deactivation
    function test_givenPolicyDeactivatedInKernel()
        public
        givenEnabled
        givenPolicyDeactivatedInKernel
    {
        assertFalse(timelock.isActive(), "the timelock should be deactivated in the kernel");

        vm.prank(admin);
        timelock.disable("");

        assertFalse(timelock.isEnabled(), "the timelock should be disabled while deactivated");
    }

    // when the caller holds the emergency role
    //   given the config policy is already disabled
    //     [X] it disables the timelock
    // The incident flow contains the config first and the timelock second; the order must not
    // matter
    function test_whenCallerIsEmergency_givenConfigDisabled()
        public
        givenEnabled
        givenConfigDisabled
    {
        assertFalse(config.isEnabled(), "the config policy should be disabled");

        vm.prank(emergency);
        timelock.disable("");

        assertFalse(timelock.isEnabled(), "the timelock should be disabled after the config");
    }
}
