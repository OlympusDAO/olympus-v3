// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

contract RevenueDistributorConfigTimelockSetGracePeriodTest is RevenueDistributorTest {
    // Scenarios: LC-P04
    function test_whenBoundaryPeriodsSet_storesEachValue() public {
        uint32[2] memory periods = [uint32(1), type(uint32).max];

        // The fixed two-value loop exercises each semantic boundary.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i; i < periods.length; ++i) {
            vm.prank(admin);
            configTimelock.setGracePeriod(periods[i]);
            assertEq(configTimelock.gracePeriod(), periods[i], "boundary period stored");
        }
        // forge-lint: disable-end(calls-loop)
    }

    // Scenarios: LC-P04, LC-L02
    function test_whenAdminSetsNonzeroPeriod_storesValue(uint32 period_, bool active_) public {
        // bound() guarantees that the result fits uint32.
        // forge-lint: disable-next-line(unsafe-typecast)
        period_ = uint32(bound(period_, 1, type(uint32).max));
        vm.assume(period_ != configTimelock.gracePeriod());
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
        }
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(configTimelock));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(admin);
        configTimelock.setGracePeriod(period_);

        assertEq(configTimelock.gracePeriod(), period_, "grace period stored");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    // Scenarios: LC-P05
    function test_whenAdminSetsCurrentGracePeriod_emitsEvent(bool active_) public {
        uint32 currentPeriod = configTimelock.gracePeriod();
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
        }
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(configTimelock));
        emit IGracePeriod.GracePeriodSet(currentPeriod);
        vm.prank(admin);
        configTimelock.setGracePeriod(currentPeriod);

        assertEq(configTimelock.gracePeriod(), currentPeriod, "grace period unchanged");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    // Scenarios: LC-I03
    function test_whenAdminSetsZeroPeriod_reverts() public {
        uint32 gracePeriod = configTimelock.gracePeriod();

        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        configTimelock.setGracePeriod(0);

        assertEq(configTimelock.gracePeriod(), gracePeriod, "grace period unchanged");
    }

    // Scenarios: LC-L01
    function test_whenDisabled_revertsBeforeAuthorizationAndValidation(
        address caller_,
        uint32 period_
    ) public {
        vm.prank(emergency);
        configTimelock.disable("");
        uint32 gracePeriod = configTimelock.gracePeriod();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        configTimelock.setGracePeriod(period_);

        assertEq(configTimelock.gracePeriod(), gracePeriod, "grace period unchanged");
    }

    // Scenarios: LC-A04
    function test_whenNonAdminSetsPeriod_reverts(address caller_, uint32 period_) public {
        vm.assume(caller_ != admin);
        uint32 gracePeriod = configTimelock.gracePeriod();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        configTimelock.setGracePeriod(period_);

        assertEq(configTimelock.gracePeriod(), gracePeriod, "grace period unchanged");
    }
}
