// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansRiskConfigTimelockSetGracePeriodTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-GRACE-N01, BLRCT-GRACE-P01.
    function test_whenGraceSet(uint32 period_) public {
        uint32 period = uint32(bound(period_, 1, type(uint32).max));
        uint48 transition = _timelock.lastTransitionAt();
        vm.expectEmit(address(_timelock));
        emit IGracePeriod.GracePeriodSet(period);
        _timelock.setGracePeriod(period);
        assertEq(_timelock.gracePeriod(), period, "exact grace");
        vm.expectEmit(address(_timelock));
        emit IGracePeriod.GracePeriodSet(period);
        _timelock.setGracePeriod(period);
        assertEq(_timelock.lastTransitionAt(), transition, "same value does not reset transition");
    }

    // Scenarios: BLRCT-GRACE-I01.
    function test_whenZeroGrace_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        _timelock.setGracePeriod(0);
    }

    // Scenarios: BLRCT-GRACE-A01.
    function test_whenUnauthorized_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _timelock.setGracePeriod(1);
    }

    // Scenarios: BLRCT-GRACE-L01.
    function test_givenInactive_whenGraceSet_reverts(bool enabled_) public {
        _setState(_timelock, false, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        _timelock.setGracePeriod(0);
    }

    // Scenarios: BLRCT-GRACE-L02.
    function test_givenDisabled_whenGraceSet_reverts() public {
        _timelock.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        _timelock.setGracePeriod(0);
    }
}
