// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskSetGracePeriodTest is RevenueDistributorTaskTest {
    // Scenarios: LC-P04, LC-L02.
    function test_whenAdminSetsPositiveGracePeriod_updatesValue(
        uint32 period_,
        bool active_
    ) public {
        period_ = _boundUint32(period_, 1, type(uint32).max);
        uint32 currentPeriod = task.gracePeriod();
        if (period_ == currentPeriod) {
            period_ = currentPeriod == type(uint32).max ? currentPeriod - 1 : currentPeriod + 1;
        }
        if (!active_) _deactivateTask();
        uint48 transitionAt = task.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(task));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(admin);
        task.setGracePeriod(period_);

        assertEq(task.gracePeriod(), period_, "grace period equals input");
        assertEq(task.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    // Scenarios: LC-I03.
    function test_whenAdminSetsZeroGracePeriod_reverts() public {
        uint32 periodBefore = task.gracePeriod();

        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        task.setGracePeriod(0);

        assertEq(task.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: LC-P05.
    function test_whenAdminSetsCurrentGracePeriod_emitsEvent(bool active_) public {
        uint32 currentPeriod = task.gracePeriod();
        if (!active_) _deactivateTask();
        uint48 transitionAt = task.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(task));
        emit IGracePeriod.GracePeriodSet(currentPeriod);
        vm.prank(admin);
        task.setGracePeriod(currentPeriod);

        assertEq(task.gracePeriod(), currentPeriod, "same grace period retained");
        assertEq(task.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    // Scenarios: LC-L01.
    function test_givenDisabled_whenGracePeriodSet_revertsBeforeOtherChecks(
        address caller_,
        uint32 period_,
        bool active_
    ) public {
        _disableTask("");
        if (!active_) _deactivateTask();
        uint32 periodBefore = task.gracePeriod();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        task.setGracePeriod(period_);

        assertEq(task.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: LC-A04.
    function test_givenEnabled_whenNonAdminSetsGracePeriod_reverts(
        address caller_,
        uint32 period_
    ) public {
        vm.assume(caller_ != admin);
        uint32 periodBefore = task.gracePeriod();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        task.setGracePeriod(period_);

        assertEq(task.gracePeriod(), periodBefore, "grace period unchanged");
    }
}
