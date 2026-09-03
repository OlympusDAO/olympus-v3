// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockSetGracePeriodTest is BurnerLoansConfigTimelockTest {
    // setGracePeriod
    // given the policy is constructed
    //  when gracePeriod is queried
    //   then it returns the default Burner Loans re-enable grace period
    function test_givenConstructed_setsDefaultGracePeriod() public view {
        assertEq(
            configTimelock.gracePeriod(),
            BurnerLoansConstants.REENABLE_GRACE_PERIOD,
            "grace period"
        );
    }

    // setGracePeriod
    // given caller does not have the admin role
    //  when setGracePeriod is called while enabled
    //   then it reverts
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        configTimelock.setGracePeriod(BurnerLoansConstants.REENABLE_GRACE_PERIOD);
    }

    // setGracePeriod
    // given new grace period is zero
    //  when setGracePeriod is called by admin while enabled
    //   then it reverts
    function test_givenZeroGracePeriod_reverts() public {
        vm.prank(admin);
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        configTimelock.setGracePeriod(0);
    }

    // setGracePeriod
    // given the policy is disabled
    //  when setGracePeriod is called by admin
    //   then it reverts
    function test_givenDisabled_reverts() public {
        vm.prank(emergency);
        configTimelock.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.setGracePeriod(BurnerLoansConstants.REENABLE_GRACE_PERIOD);
    }

    // setGracePeriod
    // given new grace period is non-zero
    //  when setGracePeriod is called by admin while enabled
    //   then it stores the grace period
    function test_givenAdminCaller_setsGracePeriod(uint32 gracePeriod_) public {
        gracePeriod_ = uint32(bound(gracePeriod_, 1, type(uint32).max));

        vm.prank(admin);
        vm.expectEmit(false, false, false, true, address(configTimelock));
        emit IGracePeriod.GracePeriodSet(gracePeriod_);
        configTimelock.setGracePeriod(gracePeriod_);

        assertEq(configTimelock.gracePeriod(), gracePeriod_, "grace period");
    }

    // setGracePeriod
    // given new grace period is the maximum uint32 value
    //  when setGracePeriod is called by admin while enabled
    //   then it stores the grace period
    function test_givenMaxUint32GracePeriod_setsGracePeriod() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true, address(configTimelock));
        emit IGracePeriod.GracePeriodSet(type(uint32).max);
        configTimelock.setGracePeriod(type(uint32).max);

        assertEq(configTimelock.gracePeriod(), type(uint32).max, "grace period");
    }
}
