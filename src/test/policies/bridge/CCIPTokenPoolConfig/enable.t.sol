// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";

// Contracts
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_enable is CCIPTokenPoolConfigTest {
    // given the policy is enabled
    //   [X] it reverts with NotDisabled
    // Repeating the call is not idempotent: the second enable reverts
    function test_givenEnabled_reverts() public givenEnabled {
        _expectRevertNotDisabled();
        vm.prank(admin);
        config.enable("");
    }

    // given the policy is enabled
    //   when the caller does not hold the admin role
    //     [X] it reverts with NotDisabled
    // Pins the masking order: the givenDisabled modifier runs before the authorization hook, so
    // the lifecycle error hides the role error from an unauthorized prober.
    function test_givenEnabled_whenCallerIsNotAdmin_reverts() public givenEnabled {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotDisabled();
        vm.prank(caller);
        config.enable("");
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The fuzz excludes the admin account and the zero address
    function test_whenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.enable("");
    }

    // when the caller holds only the emergency role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // Role asymmetry: emergency may disable but not enable
    function test_whenCallerIsEmergency_reverts() public {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(emergency);
        config.enable("");
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // Role asymmetry: the bridge admin restarts the policy only through reEnable
    function test_whenCallerIsBridgeAdmin_reverts() public {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        config.enable("");
    }

    // when the caller holds only the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsBridgeRateLimiter_reverts() public {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        config.enable("");
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with ROLES_RequireRole("admin")
    // The operator is accepted on the route and rate limit functions only, never on the
    // lifecycle. Setup: enable, set the operator, disable, then call as the operator.
    function test_whenCallerIsConfigOperator_reverts()
        public
        givenEnabled
        givenConfigOperatorSet
        givenDisabled
    {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(operator);
        config.enable("");
    }

    // when the caller holds the admin role
    //   [X] it sets isEnabled to true
    //   [X] it sets lastTransitionAt to the current timestamp
    //   [X] it emits Enabled
    //   [X] it emits Transition with the caller, true, the payload and the timestamp
    // The main happy path with an empty payload; both state fields are asserted together
    function test_whenCallerIsAdmin() public {
        uint48 timestamp = uint48(vm.getBlockTimestamp());

        vm.expectEmit(true, true, true, true, address(config));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, true, true, address(config));
        emit IEnablerV2.Transition(admin, true, "", timestamp);
        vm.prank(admin);
        config.enable("");

        assertTrue(config.isEnabled(), "the policy should be enabled");
        assertEq(
            config.lastTransitionAt(),
            timestamp,
            "lastTransitionAt should be the enable timestamp"
        );
    }

    // when the payload is not empty
    //   [X] it enables the policy
    //   [X] it emits Transition carrying the payload verbatim
    // The payload is never decoded; authorization must not depend on it. Fuzzed bytes.
    function test_whenDataIsNotEmpty(bytes calldata data_) public {
        vm.assume(data_.length > 0);
        uint48 timestamp = uint48(vm.getBlockTimestamp());

        vm.expectEmit(true, true, true, true, address(config));
        emit IEnablerV2.Transition(admin, true, data_, timestamp);
        vm.prank(admin);
        config.enable(data_);

        assertTrue(config.isEnabled(), "the policy should be enabled");
    }

    // given the policy was enabled and then disabled
    //   [X] it enables the policy again
    //   [X] it updates lastTransitionAt to the new timestamp
    // The second producer state of the disabled flag; a time skip separates the timestamps
    function test_givenDisabledAfterEnable() public givenEnabled givenDisabled {
        uint48 disableTimestamp = config.lastTransitionAt();
        skip(1 hours);
        uint48 enableTimestamp = uint48(vm.getBlockTimestamp());

        vm.prank(admin);
        config.enable("");

        assertTrue(config.isEnabled(), "the policy should be enabled again");
        assertEq(
            config.lastTransitionAt(),
            enableTimestamp,
            "lastTransitionAt should be the second enable timestamp"
        );
        assertGt(
            enableTimestamp,
            disableTimestamp,
            "the enable timestamp should be later than the disable timestamp"
        );
    }

    // given the policy was disabled and the grace window has expired
    //   [X] it enables the policy
    // The admin enable path is not grace-gated; only reEnable is, so the admin restart stays
    // available after the window closes.
    function test_givenGraceExpired() public givenEnabled givenDisabled givenGraceExpired {
        assertEq(
            vm.getBlockTimestamp(),
            uint256(graceDeadline) + 1,
            "the block timestamp should sit one second past the grace deadline"
        );

        vm.prank(admin);
        config.enable("");

        assertTrue(config.isEnabled(), "the policy should be enabled past the grace window");
    }

    // given the policy was deactivated in the kernel
    //   [X] it enables the policy
    // The functions do not check kernel.isPolicyActive and the ROLES address stays cached after
    // DeactivatePolicy. Pins the absent guard as documented behavior.
    function test_givenPolicyDeactivatedInKernel() public givenPolicyDeactivatedInKernel {
        assertFalse(config.isActive(), "the policy should be deactivated in the kernel");

        vm.prank(admin);
        config.enable("");

        assertTrue(config.isEnabled(), "the policy should be enabled while deactivated");
    }
}
