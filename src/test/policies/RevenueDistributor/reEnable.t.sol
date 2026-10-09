// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Scenario amounts stay inline for accounting clarity.
// forge-lint: disable-start(literal-instead-of-constant)

import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {Actions} from "src/Kernel.sol";
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorHarness} from "./fixtures/RevenueDistributorHarness.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorReEnableTest is RevenueDistributorTest {
    // Scenarios: LC-P03
    function test_givenDistributorDisabled_whenRevenueAdminReEnables_thenDistributionResumes()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 10);
        vm.prank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, bob);
        vm.prank(emergency);
        distributor.disable("");
        vm.prank(bob);
        distributor.reEnable();
        distributor.distribute(address(token));
        assertEq(token.balanceOf(alice), 3, "configured recipient receives its share");
        assertEq(token.balanceOf(address(treasury)), 7, "Treasury receives the remainder");
    }

    // Scenarios: LC-A02
    function test_givenDistributorDisabled_whenUnauthorizedCallerReEnables_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != bob);
        vm.prank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, bob);
        vm.prank(emergency);
        distributor.disable("");
        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        distributor.reEnable();
    }

    // given the distributor was disabled with a managed balance
    //  when admin re-enables it within grace and a caller distributes
    //   then the held balance follows the existing route
    // Scenarios: LC-P03
    function test_givenDisabled_whenReEnabled_thenStoredBalanceDistributes()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 10);
        vm.prank(emergency);
        distributor.disable("");
        vm.prank(admin);
        distributor.reEnable();

        vm.prank(bob);
        distributor.distribute(address(token));
        assertEq(token.balanceOf(alice), 3, "route survives disablement");
        assertEq(token.balanceOf(address(treasury)), 7, "residual reaches Treasury");
    }

    // Scenarios: LC-I02
    function test_givenNeverEnabled_whenAuthorizedCallerReEnables_reverts() public {
        RevenueDistributorHarness fresh = new RevenueDistributorHarness(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(fresh));

        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(admin);
        fresh.reEnable();

        assertFalse(fresh.isEnabled(), "never-enabled policy remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "never-enabled timestamp remains zero");
    }

    // Scenarios: LC-I06
    function test_givenEnabled_whenReEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(admin);
        distributor.reEnable();
    }

    // Scenarios: LC-P03
    function test_givenGraceDeadline_whenAdminReEnables_succeeds() public {
        vm.prank(admin);
        distributor.disable("");
        uint48 deadline = distributor.lastTransitionAt() + distributor.gracePeriod();
        vm.warp(deadline);

        vm.prank(admin);
        distributor.reEnable();

        assertTrue(distributor.isEnabled(), "grace deadline remains inclusive");
        assertEq(distributor.lastTransitionAt(), deadline, "deadline re-enable records timestamp");
    }

    // Scenarios: LC-I07
    function test_givenGraceExpired_whenAdminReEnables_reverts() public {
        vm.prank(admin);
        distributor.disable("");
        uint48 deadline = distributor.lastTransitionAt() + distributor.gracePeriod();
        vm.warp(uint256(deadline) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(admin);
        distributor.reEnable();

        assertFalse(distributor.isEnabled(), "expired re-enable preserves disabled state");
    }

    // Scenarios: LC-L02
    function test_givenPolicyInactiveAndDisabled_whenPermittedCallerReEnables_succeeds(
        bool adminCalls_
    ) public {
        vm.startPrank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, bob);
        distributor.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        vm.stopPrank();

        vm.prank(adminCalls_ ? admin : bob);
        distributor.reEnable();

        assertTrue(distributor.isEnabled(), "Kernel inactivity does not gate inherited re-enable");
    }
}
// forge-lint: disable-end(literal-instead-of-constant)
