// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";

// Contracts
import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_disable is CCIPBridgeConfigTest {
    // given the policy has never been enabled
    //   [X] it reverts with NotEnabled
    function test_givenNeverEnabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.disable("");
    }

    // given the policy was enabled and then disabled
    //   [X] it reverts with NotEnabled
    // The second producer state of the disabled flag: a double disable is not idempotent
    function test_givenDisabledAfterEnable_reverts() public givenEnabled givenDisabled {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.disable("");
    }

    // given the policy has never been enabled
    //   when the caller holds neither the emergency nor the admin role
    //     [X] it reverts with NotEnabled
    // Pins the masking order: the givenEnabled modifier runs before the authorization hook
    function test_givenNeverEnabled_whenCallerIsNotAuthorized_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.disable("");
    }

    // when the caller holds neither the emergency nor the admin role
    //   [X] it reverts with NotAuthorised
    // The fuzz excludes the admin and emergency accounts and the zero address
    function test_whenCallerIsNotEmergencyOrAdmin_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != emergency);
        vm.assume(caller_ != address(0));

        _expectRevertNotAuthorised();
        vm.prank(caller_);
        config.disable("");
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with NotAuthorised
    // Role asymmetry: the bridge admin may contain routes and reEnable but never freeze
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled {
        _expectRevertNotAuthorised();
        vm.prank(bridgeAdmin);
        config.disable("");
    }

    // when the caller holds only the bridge rate limiter role
    //   [X] it reverts with NotAuthorised
    function test_whenCallerIsBridgeRateLimiter_reverts() public givenEnabled {
        _expectRevertNotAuthorised();
        vm.prank(bridgeRateLimiter);
        config.disable("");
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with NotAuthorised
    // The operator is accepted on the route and rate limit functions only, never on the
    // lifecycle.
    function test_whenCallerIsConfigOperator_reverts() public givenEnabled givenConfigOperatorSet {
        _expectRevertNotAuthorised();
        vm.prank(operator);
        config.disable("");
    }

    // when the caller holds the admin role
    //   [X] it sets isEnabled to false
    //   [X] it sets lastTransitionAt to the current timestamp
    //   [X] it emits Disabled
    //   [X] it emits Transition with the caller, false, the payload and the timestamp
    // The disable timestamp is the reference point of the reEnable grace window
    function test_whenCallerIsAdmin() public givenEnabled {
        uint48 enableTimestamp = config.lastTransitionAt();
        // The skip separates the enable timestamp from the disable timestamp, so the write is
        // observable
        skip(1 hours);
        uint48 disableTimestamp = uint48(vm.getBlockTimestamp());

        vm.expectEmit(true, true, true, true, address(config));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, true, true, address(config));
        emit IEnablerV2.Transition(admin, false, "", disableTimestamp);
        vm.prank(admin);
        config.disable("");

        assertFalse(config.isEnabled(), "the policy should be disabled");
        assertEq(
            config.lastTransitionAt(),
            disableTimestamp,
            "lastTransitionAt should be the disable timestamp"
        );
        assertGt(
            disableTimestamp,
            enableTimestamp,
            "the disable timestamp should be later than the enable timestamp"
        );
    }

    // when the caller holds the emergency role
    //   [X] it sets isEnabled to false
    //   [X] it emits Disabled and Transition
    // The second authorized caller class gets its own success case
    function test_whenCallerIsEmergency() public givenEnabled {
        uint48 disableTimestamp = uint48(vm.getBlockTimestamp());

        vm.expectEmit(true, true, true, true, address(config));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, true, true, address(config));
        emit IEnablerV2.Transition(emergency, false, "", disableTimestamp);
        vm.prank(emergency);
        config.disable("");

        assertFalse(config.isEnabled(), "the policy should be disabled by the emergency role");
        assertEq(
            config.lastTransitionAt(),
            disableTimestamp,
            "lastTransitionAt should be the disable timestamp"
        );
    }

    // when the payload is not empty
    //   [X] it disables the policy
    //   [X] it emits Transition carrying the payload verbatim
    // The payload is never decoded; authorization must not depend on it. Fuzzed bytes.
    function test_whenDataIsNotEmpty(bytes calldata data_) public givenEnabled {
        vm.assume(data_.length > 0);
        uint48 disableTimestamp = uint48(vm.getBlockTimestamp());

        vm.expectEmit(true, true, true, true, address(config));
        emit IEnablerV2.Transition(admin, false, data_, disableTimestamp);
        vm.prank(admin);
        config.disable(data_);

        assertFalse(config.isEnabled(), "the policy should be disabled");
    }

    // given the policy was disabled and then re-enabled through reEnable
    //   [X] it disables the policy again
    // The enabled flag written by reEnable is accepted by disable exactly like the one written
    // by enable.
    function test_givenReEnabledAfterDisable() public givenEnabled givenDisabled givenReEnabled {
        assertTrue(config.isEnabled(), "the policy should be enabled through reEnable");

        vm.prank(admin);
        config.disable("");

        assertFalse(config.isEnabled(), "the policy should be disabled after the re-enable");
    }
}
