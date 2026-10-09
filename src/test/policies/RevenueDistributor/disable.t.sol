// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Actions} from "src/Kernel.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorDisableTest is RevenueDistributorTest {
    // Scenarios: LC-P02
    function test_whenPermittedCallerDisables_preservesConfiguration(
        bool adminCalls_,
        bytes memory data_
    ) public {
        vm.assume(data_.length < 256);
        address caller = adminCalls_ ? admin : emergency;
        uint48 transitionTime = distributor.lastTransitionAt() + 1;
        vm.warp(transitionTime);

        vm.expectEmit(false, false, false, false, address(distributor));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IEnablerV2.Transition(caller, false, data_, transitionTime);
        vm.prank(caller);
        distributor.disable(data_);

        assertFalse(distributor.isEnabled(), "permitted caller disables distributor");
        assertEq(distributor.lastTransitionAt(), transitionTime, "disable records timestamp");
        assertEq(
            distributor.configOperator(),
            address(configTimelock),
            "disable preserves config operator"
        );
    }

    // Scenarios: LC-I05
    function test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization(
        address caller_
    ) public {
        vm.prank(admin);
        distributor.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        distributor.disable("");
    }

    // Scenarios: LC-A03
    function test_givenEnabled_whenUnauthorizedCallerDisables_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != emergency);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        distributor.disable("");

        assertTrue(distributor.isEnabled(), "unauthorized disable preserves enabled state");
    }

    // Scenarios: LC-L02
    function test_givenPolicyInactive_whenPermittedCallerDisables_succeeds(
        bool adminCalls_
    ) public {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));

        vm.prank(adminCalls_ ? admin : emergency);
        distributor.disable("");

        assertFalse(distributor.isEnabled(), "Kernel inactivity does not gate inherited disable");
    }
}
