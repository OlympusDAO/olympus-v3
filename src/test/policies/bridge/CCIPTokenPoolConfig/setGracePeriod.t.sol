// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

// Contracts
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {CCIPTokenPoolConfigTest} from "./CCIPTokenPoolConfigTest.sol";

contract CCIPTokenPoolConfigTests_setGracePeriod is CCIPTokenPoolConfigTest {
    // given the policy has never been enabled
    //   [X] it reverts with NotEnabled
    function test_givenDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.setGracePeriod(1 days);
    }

    // given the policy was enabled and then disabled
    //   [X] it reverts with NotEnabled
    // Pins the operational meaning of the gate: the window cannot be extended after a disable
    function test_givenDisabledAfterEnable_reverts() public givenEnabled givenDisabled {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.setGracePeriod(1 days);

        assertEq(config.gracePeriod(), GRACE_PERIOD, "the grace period should be unchanged");
    }

    // given the policy is disabled
    //   when the caller does not hold the admin role
    //     [X] it reverts with NotEnabled
    // Pins the masking order: the lifecycle gate answers before the authorization hook
    function test_givenDisabled_whenCallerIsNotAdmin_reverts() public {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertNotEnabled();
        vm.prank(caller);
        config.setGracePeriod(1 days);
    }

    // given the policy is disabled
    //   when the period is zero
    //     [X] it reverts with NotEnabled
    // Pins the masking order: the lifecycle gate answers before the value check
    function test_givenDisabled_whenPeriodIsZero_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(admin);
        config.setGracePeriod(0);
    }

    // when the caller does not hold the admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // The fuzz excludes the admin account and the zero address
    function test_whenCallerIsNotAdmin_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(0));

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller_);
        config.setGracePeriod(1 days);
    }

    // when the caller does not hold the admin role
    //   when the period is zero
    //     [X] it reverts with ROLES_RequireRole("admin")
    // Pins the masking order: the role check answers before the value check
    function test_whenCallerIsNotAdmin_whenPeriodIsZero_reverts() public givenEnabled {
        address caller = makeAddr("unauthorizedCaller");

        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(caller);
        config.setGracePeriod(0);
    }

    // when the caller holds only the bridge admin role
    //   [X] it reverts with ROLES_RequireRole("admin")
    // Role asymmetry: the role that consumes the window through reEnable cannot set its length
    function test_whenCallerIsBridgeAdmin_reverts() public givenEnabled {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(bridgeAdmin);
        config.setGracePeriod(1 days);
    }

    // given the config operator is set
    //   when the caller is the config operator
    //     [X] it reverts with ROLES_RequireRole("admin")
    function test_whenCallerIsConfigOperator_reverts() public givenEnabled givenConfigOperatorSet {
        _expectRevertRequireRole(ADMIN_ROLE);
        vm.prank(operator);
        config.setGracePeriod(1 days);
    }

    // when the period is zero
    //   [X] it reverts with GracePeriod_ZeroPeriod
    function test_whenPeriodIsZero_reverts() public givenEnabled {
        vm.expectRevert(abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector));
        vm.prank(admin);
        config.setGracePeriod(0);

        assertEq(config.gracePeriod(), GRACE_PERIOD, "the grace period should be unchanged");
    }

    // when the parameters are valid
    //   [X] it updates gracePeriod to the new value
    //   [X] it emits GracePeriodSet with the new value
    function test_whenParametersAreValid() public givenEnabled {
        uint32 newPeriod = 7 days;

        vm.expectEmit(true, true, true, true, address(config));
        emit IGracePeriod.GracePeriodSet(newPeriod);
        vm.prank(admin);
        config.setGracePeriod(newPeriod);

        assertEq(config.gracePeriod(), newPeriod, "the grace period should be the new value");
    }

    // when the period is one second
    //   [X] it updates gracePeriod to one
    // The zero check is an equality, so one is the smallest accepted window
    function test_whenPeriodIsOne() public givenEnabled {
        vm.expectEmit(true, true, true, true, address(config));
        emit IGracePeriod.GracePeriodSet(1);
        vm.prank(admin);
        config.setGracePeriod(1);

        assertEq(config.gracePeriod(), 1, "the grace period should be one second");
    }

    // when the period is the uint32 maximum
    //   [X] it updates gracePeriod to type(uint32).max
    // No upper bound exists; pins the absent guard
    function test_whenPeriodIsMax() public givenEnabled {
        vm.expectEmit(true, true, true, true, address(config));
        emit IGracePeriod.GracePeriodSet(type(uint32).max);
        vm.prank(admin);
        config.setGracePeriod(type(uint32).max);

        assertEq(
            config.gracePeriod(),
            type(uint32).max,
            "the grace period should be the uint32 maximum"
        );
    }

    // when the period is any non-zero value
    //   [X] it updates gracePeriod to the argument
    // Fuzzed over the valid interval [1, type(uint32).max]
    function test_whenPeriodIsNonZero(uint32 period_) public givenEnabled {
        // The valid interval of the setter is [1, type(uint32).max]: zero is the only rejected
        // value
        uint32 boundedPeriod = uint32(bound(period_, 1, type(uint32).max));

        vm.prank(admin);
        config.setGracePeriod(boundedPeriod);

        assertEq(config.gracePeriod(), boundedPeriod, "the grace period should be the argument");
    }

    // when the period equals the current value
    //   [X] it writes and emits GracePeriodSet
    // Writing the value that is already set succeeds rather than reverting
    function test_whenValueEqualsCurrentValue() public givenEnabled {
        uint32 currentPeriod = config.gracePeriod();
        assertEq(
            currentPeriod,
            GRACE_PERIOD,
            "the grace period should start at the deployed value"
        );

        vm.expectEmit(true, true, true, true, address(config));
        emit IGracePeriod.GracePeriodSet(currentPeriod);
        vm.prank(admin);
        config.setGracePeriod(currentPeriod);

        assertEq(config.gracePeriod(), currentPeriod, "the grace period should be unchanged");
    }

    // given the grace period was updated
    //   given the policy was then disabled
    //     [X] the reEnable deadline uses the updated value
    // Composition with reEnable: the value in force at disable time governs the window, so an
    // update made while enabled applies to the next disable.
    function test_givenGracePeriodUpdated_givenDisabledAfterEnable() public givenEnabled {
        // The new window is shorter than the deployed one (1 day against 3 days), so a
        // timestamp inside the deployed window can sit outside the updated one
        uint32 newPeriod = 1 days;
        vm.prank(admin);
        config.setGracePeriod(newPeriod);

        vm.prank(admin);
        config.disable("");

        // deadline = lastTransitionAt + gracePeriod, with gracePeriod at the updated value
        uint48 updatedDeadline = config.lastTransitionAt() + newPeriod;
        // Land one second past the updated deadline, which is still 2 days inside the deployed
        // 3-day window
        skip(uint256(updatedDeadline) + 1 - vm.getBlockTimestamp());

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, updatedDeadline)
        );
        vm.prank(bridgeAdmin);
        config.reEnable();

        assertFalse(config.isEnabled(), "the policy should stay disabled past the updated window");
    }
}
