// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {PolicyEnablerTest} from "./PolicyEnablerTest.sol";

contract PolicyEnablerEnableTest is PolicyEnablerTest {
    event Enabled();

    // given the caller does not have the emergency or admin roles
    //  [X] it reverts
    // given the policy is enabled
    //  [X] it reverts
    // given the caller has the admin role
    //  [X] it sets the enabled flag to true
    //  [X] it emits the Enabled event
    // given the caller has the emergency role
    //  [X] it sets the enabled flag to true
    //  [X] it emits the Enabled event
    // given the policy has custom enable logic
    //  given the custom enable logic reverts
    //   [X] it reverts
    //  [X] it calls the implementation-specific enable function
    //  [X] it sets the enabled flag to true
    //  [X] it emits the Enabled event

    function test_callerNotEmergencyOrAdminRole_reverts(address caller_) public {
        vm.assume(caller_ != EMERGENCY && caller_ != ADMIN);

        // Expect revert
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);

        // Call function
        vm.prank(caller_);
        policyEnabler.enable(enableData);
    }

    function test_policyEnabled_reverts() public givenEnabled {
        // Expect revert
        vm.expectRevert(PolicyEnabler.NotDisabled.selector);

        // Call function
        vm.prank(EMERGENCY);
        policyEnabler.enable(enableData);
    }

    function test_callerHasAdminRole() public {
        // Expect event
        vm.expectEmit();
        emit Enabled();

        // Call function
        vm.prank(ADMIN);
        policyEnabler.enable(enableData);

        // Assert state
        _assertStateVariables(true, 0, 0, 0);
    }

    function test_callerHasEmergencyRole() public {
        // Expect event
        vm.expectEmit();
        emit Enabled();

        // Call function
        vm.prank(EMERGENCY);
        policyEnabler.enable(enableData);

        // Assert state
        _assertStateVariables(true, 0, 0, 0);
    }

    function test_customLogic_reverts()
        public
        givenPolicyHasCustomLogic
        givenPolicyEnableCustomLogicReverts
        givenEnableData(1)
    {
        // Expect revert
        vm.expectRevert("Enable should revert");

        // Call function
        vm.prank(EMERGENCY);
        policyEnabler.enable(enableData);
    }

    function test_customLogic(
        uint256 value_
    ) public givenPolicyHasCustomLogic givenEnableData(value_) {
        // Expect event
        vm.expectEmit();
        emit Enabled();

        // Call function
        vm.prank(EMERGENCY);
        policyEnabler.enable(enableData);

        // Assert state
        _assertStateVariables(true, value_, 0, 0);
    }
}
