// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ICCIPBridgeConfigTimelock} from "src/policies/interfaces/bridge/ICCIPBridgeConfigTimelock.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPBridgeConfigTimelockTest} from "./CCIPBridgeConfigTimelockTest.sol";

contract CCIPBridgeConfigTimelockTests_enable is CCIPBridgeConfigTimelockTest {
    // given the timelock is enabled
    //   [X] it reverts with NotDisabled
    function test_givenEnabled_reverts() public givenEnabled {
        _expectRevertNotDisabled();
        vm.prank(admin);
        timelock.enable("");
    }

    // given the timelock is enabled
    //   when the caller is not an admin
    //     [X] it reverts with NotDisabled
    // Pins the guard order: the lifecycle modifier answers before the role check, so an
    // unauthorized caller probing an enabled timelock learns only the lifecycle state
    function test_givenEnabled_whenCallerIsNotAdmin_reverts() public givenEnabled {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotDisabled();
        vm.prank(caller);
        timelock.enable("");
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // Fuzzed; excludes the admin account
    function test_whenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        timelock.enable("");
    }

    // when the caller holds the emergency role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // Role asymmetry: emergency may disable but not enable
    function test_whenCallerIsEmergency_reverts() public {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(emergency);
        timelock.enable("");
    }

    // when the caller holds the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // Role asymmetry: the bridge admin may reEnable within grace but never enable
    function test_whenCallerIsBridgeAdmin_reverts() public {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        timelock.enable("");
    }

    // when the caller holds the bridge rate limiter role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The bridge rate limiter holds no timelock authority at all
    function test_whenCallerIsBridgeRateLimiter_reverts() public {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeRateLimiter);
        timelock.enable("");
    }

    // given the config policy has been deactivated in the kernel
    //   when the caller is not an admin
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the guard order: the role check answers before the config-activity hook
    function test_givenConfigDeactivatedInKernel_whenCallerIsNotAdmin_reverts()
        public
        givenConfigDeactivatedInKernel
    {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(thirdParty);
        timelock.enable("");
    }

    // given the config policy has been deactivated in the kernel
    //   [X] it reverts with CCIPBridgeConfigTimelock_ConfigNotActive carrying the config
    //       address
    function test_givenConfigDeactivatedInKernel_reverts() public givenConfigDeactivatedInKernel {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPBridgeConfigTimelock.CCIPBridgeConfigTimelock_ConfigNotActive.selector,
                address(config)
            )
        );
        vm.prank(admin);
        timelock.enable("");
    }

    // when the caller is the admin
    //   [X] it sets isEnabled true
    //   [X] it sets lastTransitionAt to the current timestamp
    //   [X] it emits Enabled
    //   [X] it emits Transition with the caller, true, the payload and the timestamp
    function test_whenCallerIsAdmin() public {
        uint48 timestamp = uint48(vm.getBlockTimestamp());

        vm.expectEmit(true, true, true, true, address(timelock));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, true, true, address(timelock));
        emit IEnablerV2.Transition(admin, true, "", timestamp);
        vm.prank(admin);
        timelock.enable("");

        assertTrue(timelock.isEnabled(), "the timelock should be enabled");
        assertEq(
            timelock.lastTransitionAt(),
            timestamp,
            "lastTransitionAt should be the enable timestamp"
        );
    }

    // when the payload is not empty
    //   [X] it enables and carries the payload verbatim in the Transition event
    // The payload is never decoded; fuzzed over arbitrary bytes
    function test_whenDataIsNotEmpty(bytes calldata data_) public {
        vm.assume(data_.length > 0);
        uint48 timestamp = uint48(vm.getBlockTimestamp());

        vm.expectEmit(true, true, true, true, address(timelock));
        emit IEnablerV2.Transition(admin, true, data_, timestamp);
        vm.prank(admin);
        timelock.enable(data_);

        assertTrue(timelock.isEnabled(), "the timelock should be enabled");
    }

    // given the timelock was enabled and then disabled
    //   [X] it enables again
    // The second producer state of the disabled flag (round trip), distinct from the fresh
    // never-enabled state of the main happy path
    function test_givenDisabledAfterEnable() public givenEnabled givenDisabled {
        uint48 disableTimestamp = timelock.lastTransitionAt();
        skip(1 hours);
        uint48 enableTimestamp = uint48(vm.getBlockTimestamp());

        vm.prank(admin);
        timelock.enable("");

        assertTrue(timelock.isEnabled(), "the timelock should be enabled again");
        assertEq(
            timelock.lastTransitionAt(),
            enableTimestamp,
            "lastTransitionAt should be the second enable timestamp"
        );
        assertGt(
            enableTimestamp,
            disableTimestamp,
            "the enable timestamp should be later than the disable timestamp"
        );
    }

    // given the grace window since the last disable has expired
    //   [X] it enables
    // The admin path is not grace-gated; only reEnable is. Pins the recovery asymmetry.
    function test_givenGraceExpired() public givenEnabled givenDisabled givenGraceExpired {
        assertEq(
            vm.getBlockTimestamp(),
            uint256(graceDeadline) + 1,
            "the block timestamp should sit one second past the grace deadline"
        );

        vm.prank(admin);
        timelock.enable("");

        assertTrue(timelock.isEnabled(), "the timelock should be enabled past the grace window");
    }

    // given the config policy is disabled but still active in the kernel
    //   [X] it enables
    // The pinned asymmetry: _beforeEnable checks kernel activity, not enablement. Queueing on
    // the resulting state reverts NotEnabled on its own gate (queue passes).
    function test_givenConfigDisabled() public givenConfigDisabled {
        assertFalse(config.isEnabled(), "the config policy should be disabled");

        vm.prank(admin);
        timelock.enable("");

        assertTrue(timelock.isEnabled(), "the timelock should enable over a disabled config");
    }

    // given the config policy was deactivated and then re-activated in the kernel
    //   [X] it enables
    // The unblock path of the ConfigNotActive gate
    function test_givenConfigReactivatedInKernel() public {
        kernel.executeAction(Actions.DeactivatePolicy, address(config));
        kernel.executeAction(Actions.ActivatePolicy, address(config));

        vm.prank(admin);
        timelock.enable("");

        assertTrue(timelock.isEnabled(), "the timelock should enable after the re-activation");
    }

    // given the timelock policy has been deactivated in the kernel
    //   [X] it enables
    // The hook checks the config's activity, never the timelock's own; the cached ROLES
    // pointer keeps authorizing after deactivation
    function test_givenPolicyDeactivatedInKernel() public givenPolicyDeactivatedInKernel {
        assertFalse(timelock.isActive(), "the timelock should be deactivated in the kernel");

        vm.prank(admin);
        timelock.enable("");

        assertTrue(timelock.isEnabled(), "the timelock should be enabled while deactivated");
    }
}
