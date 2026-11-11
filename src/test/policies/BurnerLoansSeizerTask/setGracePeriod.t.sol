// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansSeizerTaskSetGracePeriodTest is BurnerLoansSeizerTaskTest {
    uint32 internal constant _ONE_DAY = 1 days;

    function test_givenConstructed_setsDefaultGracePeriod() public view {
        assertEq(_task.gracePeriod(), _GRACE_PERIOD, "default grace period");
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _task.setGracePeriod(_ONE_DAY);
    }

    function test_givenBurnerLoansAdminCaller_reverts() public {
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, _BOB);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(_BOB);
        _task.setGracePeriod(_ONE_DAY);
    }

    function test_givenZeroPeriod_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        _task.setGracePeriod(0);
    }

    function test_givenDisabled_reverts() public {
        _task.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        _task.setGracePeriod(_ONE_DAY);
    }

    function test_givenValidPeriod_setsPeriod(uint32 period_) public {
        period_ = uint32(bound(period_, 1, type(uint32).max));

        _task.setGracePeriod(period_);

        assertEq(_task.gracePeriod(), period_, "grace period should be updated");
    }

    function test_givenMaximumPeriod_setsPeriod() public {
        _task.setGracePeriod(type(uint32).max);

        assertEq(_task.gracePeriod(), type(uint32).max, "maximum grace period");
    }
}
