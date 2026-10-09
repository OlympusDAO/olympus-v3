// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorEnableTest is RevenueDistributorTest {
    // Scenarios: LC-P01
    function test_givenDisabled_whenAdminEnables_preservesConfiguration(bytes memory data_) public {
        vm.assume(data_.length < 256);
        vm.prank(admin);
        distributor.disable("disable");
        uint48 transitionTime = distributor.lastTransitionAt() + 1;
        vm.warp(transitionTime);

        vm.expectEmit(false, false, false, false, address(distributor));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IEnablerV2.Transition(admin, true, data_, transitionTime);
        vm.prank(admin);
        distributor.enable(data_);

        assertTrue(distributor.isEnabled(), "admin enables distributor");
        assertEq(distributor.lastTransitionAt(), transitionTime, "enable records timestamp");
        assertEq(
            distributor.configOperator(),
            address(configTimelock),
            "enable preserves config operator"
        );
    }

    // Scenarios: LC-I01
    function test_givenEnabled_whenEnableCalled_revertsBeforeAuthorization(address caller_) public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        distributor.enable("");
    }

    // Scenarios: LC-A01
    function test_givenDisabled_whenNonAdminEnables_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.prank(admin);
        distributor.disable("");

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        distributor.enable("");

        assertFalse(distributor.isEnabled(), "unauthorized enable preserves disabled state");
    }

    // Scenarios: LC-L02
    function test_givenPolicyInactiveAndDisabled_whenAdminEnables_succeeds() public {
        vm.startPrank(admin);
        distributor.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        distributor.enable("");
        vm.stopPrank();

        assertTrue(distributor.isEnabled(), "Kernel inactivity does not gate inherited enable");
    }
}
