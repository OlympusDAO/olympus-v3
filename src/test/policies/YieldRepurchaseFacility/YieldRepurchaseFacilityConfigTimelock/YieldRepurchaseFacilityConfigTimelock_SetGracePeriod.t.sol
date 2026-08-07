// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IYieldRepurchaseFacilityConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityConfigTimelock.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {YieldRepurchaseFacilityConfigTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityConfigTimelock/YieldRepurchaseFacilityConfigTimelockTestBase.sol";

contract YieldRepurchaseFacilityConfigTimelockTests_SetGracePeriod is
    YieldRepurchaseFacilityConfigTimelockTestBase
{
    // setGracePeriod
    // given the policy was constructed with a grace period
    //  when reading gracePeriod
    //   then it returns the constructor value
    function test_givenConstructed_setsInitialGracePeriod() public view {
        assertEq(configTimelock.gracePeriod(), gracePeriod, "grace period");
    }

    // setGracePeriod
    // given the caller does not hold the admin role
    //  when setting the grace period
    //   then it reverts with ROLES_RequireRole(admin)
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != guardian);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        configTimelock.setGracePeriod(3 days);
    }

    // setGracePeriod
    // given the new grace period is zero
    //  when the admin sets it
    //   then it reverts with GracePeriod_ZeroPeriod
    function test_givenZeroGracePeriod_reverts() public {
        vm.prank(guardian);
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        configTimelock.setGracePeriod(0);
    }

    // setGracePeriod
    // given the policy is disabled
    //  when the admin sets a valid grace period
    //   then it reverts with NotEnabled (the window is fixed while disabled)
    function test_givenDisabled_reverts() public {
        vm.prank(guardian);
        configTimelock.disable("");

        vm.prank(guardian);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.setGracePeriod(3 days);

        assertEq(configTimelock.gracePeriod(), gracePeriod, "grace period unchanged");
    }

    // setGracePeriod
    // given any non-zero grace period below MAX_GRACE_PERIOD
    //  when the admin sets it
    //   then the window is updated and GracePeriodSet is emitted
    function test_givenAdminCaller_setsGracePeriod(uint32 gracePeriod_) public {
        gracePeriod_ = uint32(bound(gracePeriod_, 1, configTimelock.MAX_GRACE_PERIOD() - 1));

        vm.expectEmit(false, false, false, true, address(configTimelock));
        emit IGracePeriod.GracePeriodSet(gracePeriod_);
        vm.prank(guardian);
        configTimelock.setGracePeriod(gracePeriod_);

        assertEq(configTimelock.gracePeriod(), gracePeriod_, "grace period");
    }

    // setGracePeriod
    // given any grace period at or above MAX_GRACE_PERIOD
    //  when the admin sets it
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_GracePeriodTooLong
    function test_givenGracePeriodAtOrAboveMax_reverts(uint32 gracePeriod_) public {
        gracePeriod_ = uint32(
            bound(gracePeriod_, configTimelock.MAX_GRACE_PERIOD(), type(uint32).max)
        );

        vm.prank(guardian);
        vm.expectRevert(
            IYieldRepurchaseFacilityConfigTimelock
                .IYieldRepurchaseFacilityConfigTimelock_GracePeriodTooLong
                .selector
        );
        configTimelock.setGracePeriod(gracePeriod_);

        assertEq(configTimelock.gracePeriod(), gracePeriod, "grace period unchanged");
    }
}
