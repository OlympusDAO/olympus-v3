// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorSetGracePeriodTest is RevenueDistributorTest {
    // Scenarios: LC-P04
    function test_whenAdminSetsPositiveGracePeriod_updatesValue(uint32 period_) public {
        vm.assume(period_ != 0);
        vm.assume(period_ != distributor.gracePeriod());
        uint48 transitionBefore = distributor.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(distributor));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(admin);
        distributor.setGracePeriod(period_);

        assertEq(distributor.gracePeriod(), period_, "grace period equals input");
        assertEq(
            distributor.lastTransitionAt(),
            transitionBefore,
            "grace update preserves transition timestamp"
        );
    }

    // Scenarios: LC-P05
    function test_whenAdminSetsCurrentGracePeriod_emitsEvent(bool active_) public {
        uint32 currentPeriod = distributor.gracePeriod();
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        }
        uint48 transitionBefore = distributor.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(distributor));
        emit IGracePeriod.GracePeriodSet(currentPeriod);
        vm.prank(admin);
        distributor.setGracePeriod(currentPeriod);

        assertEq(distributor.gracePeriod(), currentPeriod, "grace period unchanged");
        assertEq(
            distributor.lastTransitionAt(),
            transitionBefore,
            "transition timestamp unchanged"
        );
    }

    // Scenarios: LC-I03
    function test_whenAdminSetsZeroGracePeriod_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        distributor.setGracePeriod(0);
    }

    // Scenarios: LC-L01
    function test_givenDisabled_whenGracePeriodSet_revertsBeforeAuthorization(
        address caller_,
        uint32 period_
    ) public {
        vm.prank(admin);
        distributor.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        distributor.setGracePeriod(period_);
    }

    // Scenarios: LC-A04
    function test_givenEnabled_whenNonAdminSetsGracePeriod_reverts(
        address caller_,
        uint32 period_
    ) public {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        distributor.setGracePeriod(period_);
    }

    // Scenarios: LC-L02
    function test_givenPolicyInactive_whenAdminSetsGracePeriod_succeeds(uint32 period_) public {
        vm.assume(period_ != 0);
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));

        vm.prank(admin);
        distributor.setGracePeriod(period_);

        assertEq(distributor.gracePeriod(), period_, "inactive policy stores grace period");
    }
}
