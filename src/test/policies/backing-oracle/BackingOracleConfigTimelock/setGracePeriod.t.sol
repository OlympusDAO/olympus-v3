// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";

// Contracts
import {BackingOracleConfigTimelockTest, ROLESv1, IEnabler} from "./fixtures/BackingOracleConfigTimelockTest.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract BackingOracleConfigTimelockSetGracePeriodTest is BackingOracleConfigTimelockTest {
    // Scenarios: BO-TIMELOCK-SETGRACEPERIOD-01.
    function test_whenAdminChanges(uint32 period_) public {
        period_ = uint32(bound(period_, 1, type(uint32).max));
        uint48 transitioned = _timelock.lastTransitionAt();
        vm.expectEmit(address(_timelock));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(_ADMIN);
        _timelock.setGracePeriod(period_);
        assertEq(_timelock.gracePeriod(), period_, "configured grace");
        assertEq(_timelock.lastTransitionAt(), transitioned, "configuration preserves transition");
    }

    // Scenarios: BO-TIMELOCK-SETGRACEPERIOD-02.
    function test_whenBoundarySeeds() public {
        vm.prank(_ADMIN);
        _timelock.setGracePeriod(1);
        vm.prank(_ADMIN);
        _timelock.setGracePeriod(type(uint32).max);
        assertEq(_timelock.gracePeriod(), type(uint32).max, "maximum period accepted");
    }

    // Scenarios: BO-TIMELOCK-SETGRACEPERIOD-03.
    function test_whenZero_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(_ADMIN);
        _timelock.setGracePeriod(0);
    }

    // Scenarios: BO-TIMELOCK-SETGRACEPERIOD-04.
    function test_whenSameValue() public {
        vm.expectEmit(address(_timelock));
        emit IGracePeriod.GracePeriodSet(7 days);
        vm.prank(_ADMIN);
        _timelock.setGracePeriod(7 days);
        assertEq(_timelock.gracePeriod(), 7 days, "unchanged period emits event");
    }

    // Scenarios: BO-TIMELOCK-SETGRACEPERIOD-05.
    function test_whenUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != _ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _timelock.setGracePeriod(7 days);
    }

    // Scenarios: BO-TIMELOCK-SETGRACEPERIOD-07.
    function test_givenDisabled_whenSet_reverts() public {
        vm.prank(_ADMIN);
        _timelock.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_ADMIN);
        _timelock.setGracePeriod(1);
    }

    // Scenarios: BO-TIMELOCK-SETGRACEPERIOD-06.
    function test_givenInactive_whenSet_reverts() public givenTimelockInactive {
        _expectTimelockInactive();
        vm.prank(_ADMIN);
        _timelock.setGracePeriod(1);
    }
}
