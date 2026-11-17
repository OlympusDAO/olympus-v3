// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

// Contracts
import {BackingOracleTest, ROLESv1, IEnabler} from "./fixtures/BackingOracleTest.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BackingOracleSetGracePeriodTest is BackingOracleTest {
    // Scenarios: BO-SETGRACEPERIOD-01.
    function test_whenAdminChanges(uint32 period_) public givenEnabled {
        period_ = uint32(bound(period_, 1, type(uint32).max));
        uint48 transitioned = _oracle.lastTransitionAt();
        vm.expectEmit(address(_oracle));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(_ADMIN);
        _oracle.setGracePeriod(period_);
        assertEq(_oracle.gracePeriod(), period_, "configured grace");
        assertEq(_oracle.lastTransitionAt(), transitioned, "configuration preserves transition");
    }

    // Scenarios: BO-SETGRACEPERIOD-02.
    function test_whenBoundarySeeds() public givenEnabled {
        vm.prank(_ADMIN);
        _oracle.setGracePeriod(1);
        vm.prank(_ADMIN);
        _oracle.setGracePeriod(type(uint32).max);
        assertEq(_oracle.gracePeriod(), type(uint32).max, "maximum period accepted");
    }

    // Scenarios: BO-SETGRACEPERIOD-03.
    function test_whenZero_reverts() public givenEnabled {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(_ADMIN);
        _oracle.setGracePeriod(0);
    }

    // Scenarios: BO-SETGRACEPERIOD-04.
    function test_whenSameValue() public givenEnabled {
        vm.expectEmit(address(_oracle));
        emit IGracePeriod.GracePeriodSet(7 days);
        vm.prank(_ADMIN);
        _oracle.setGracePeriod(7 days);
        assertEq(_oracle.gracePeriod(), 7 days, "unchanged period emits event");
    }

    // Scenarios: BO-SETGRACEPERIOD-05.
    function test_whenUnauthorized_reverts(address caller_) public givenEnabled {
        vm.assume(caller_ != _ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _oracle.setGracePeriod(7 days);
    }

    // Scenarios: BO-SETGRACEPERIOD-07.
    function test_givenDisabled_whenSet_reverts() public {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_ADMIN);
        _oracle.setGracePeriod(1);
    }

    // Scenarios: BO-SETGRACEPERIOD-06.
    function test_givenInactive_whenSet_reverts() public givenEnabled givenInactive {
        _expectInactive();
        vm.prank(_ADMIN);
        _oracle.setGracePeriod(1);
    }
}
