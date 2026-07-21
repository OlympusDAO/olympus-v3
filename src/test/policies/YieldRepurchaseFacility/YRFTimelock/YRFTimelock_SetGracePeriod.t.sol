// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IYRFTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYRFTimelock.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {YRFTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YRFTimelock/YRFTimelockTestBase.sol";

contract YRFTimelockTests_SetGracePeriod is YRFTimelockTestBase {
    // setGracePeriod
    // given the policy was constructed with a grace period
    //  when reading gracePeriod
    //   then it returns the constructor value
    function test_givenConstructed_setsInitialGracePeriod() public view {
        assertEq(yrfTimelock.gracePeriod(), gracePeriod, "grace period");
    }

    // setGracePeriod
    // given the caller does not hold the admin role
    //  when setting the grace period
    //   then it reverts with ROLES_RequireRole(admin)
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != guardian);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        yrfTimelock.setGracePeriod(3 days);
    }

    // setGracePeriod
    // given the new grace period is zero
    //  when the admin sets it
    //   then it reverts with GracePeriod_ZeroPeriod
    function test_givenZeroGracePeriod_reverts() public {
        vm.prank(guardian);
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        yrfTimelock.setGracePeriod(0);
    }

    // setGracePeriod
    // given the policy is disabled
    //  when the admin sets a valid grace period
    //   then it reverts with NotEnabled (the window is fixed while disabled)
    function test_givenDisabled_reverts() public {
        vm.prank(guardian);
        yrfTimelock.disable("");

        vm.prank(guardian);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        yrfTimelock.setGracePeriod(3 days);

        assertEq(yrfTimelock.gracePeriod(), gracePeriod, "grace period unchanged");
    }

    // setGracePeriod
    // given any non-zero grace period below MAX_GRACE_PERIOD
    //  when the admin sets it
    //   then the window is updated and GracePeriodSet is emitted
    function test_givenAdminCaller_setsGracePeriod(uint32 gracePeriod_) public {
        gracePeriod_ = uint32(bound(gracePeriod_, 1, yrfTimelock.MAX_GRACE_PERIOD() - 1));

        vm.expectEmit(false, false, false, true, address(yrfTimelock));
        emit IGracePeriod.GracePeriodSet(gracePeriod_);
        vm.prank(guardian);
        yrfTimelock.setGracePeriod(gracePeriod_);

        assertEq(yrfTimelock.gracePeriod(), gracePeriod_, "grace period");
    }

    // setGracePeriod
    // given any grace period at or above MAX_GRACE_PERIOD
    //  when the admin sets it
    //   then it reverts with IYRFTimelock_GracePeriodTooLong
    function test_givenGracePeriodAtOrAboveMax_reverts(uint32 gracePeriod_) public {
        gracePeriod_ = uint32(
            bound(gracePeriod_, yrfTimelock.MAX_GRACE_PERIOD(), type(uint32).max)
        );

        vm.prank(guardian);
        vm.expectRevert(IYRFTimelock.IYRFTimelock_GracePeriodTooLong.selector);
        yrfTimelock.setGracePeriod(gracePeriod_);

        assertEq(yrfTimelock.gracePeriod(), gracePeriod, "grace period unchanged");
    }
}
