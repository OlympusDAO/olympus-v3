// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {PolicyEnablerTest} from "./PolicyEnablerTest.sol";

contract PolicyEnablerDisableTest is PolicyEnablerTest {
    event Disabled();

    // given the caller does not have the emergency or admin roles
    //  [X] it reverts
    // given the policy is disabled
    //  [X] it reverts
    // given the caller has the admin role
    //  [X] it sets the enabled flag to false
    //  [X] it emits the Disabled event
    // given the caller has the emergency role
    //  [X] it sets the enabled flag to false
    //  [X] it emits the Disabled event
    // given the policy has custom disable logic
    //  given the custom disable logic reverts
    //   [ X] it reverts
    //  [X] it calls the implementation-specific disable function
    //  [X] it sets the enabled flag to false
    //  [X] it emits the Disabled event

    function test_callerNotEmergencyOrAdminRole_reverts(address caller_) public {
        vm.assume(caller_ != EMERGENCY && caller_ != ADMIN);

        // Expect revert
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);

        // Call function
        vm.prank(caller_);
        policyEnabler.disable(disableData);
    }

    function test_policyDisabled_reverts() public {
        // Expect revert
        vm.expectRevert(PolicyEnabler.NotEnabled.selector);

        // Call function
        vm.prank(EMERGENCY);
        policyEnabler.disable(disableData);
    }

    function test_callerHasAdminRole() public givenEnabled {
        // Expect event
        vm.expectEmit();
        emit Disabled();

        // Call function
        vm.prank(ADMIN);
        policyEnabler.disable(disableData);

        // Assert state
        _assertStateVariables(false, 0, 0, 0);
    }

    function test_callerHasEmergencyRole() public givenEnabled {
        // Expect event
        vm.expectEmit();
        emit Disabled();

        // Call function
        vm.prank(EMERGENCY);
        policyEnabler.disable(disableData);

        // Assert state
        _assertStateVariables(false, 0, 0, 0);
    }

    function test_customLogic_reverts()
        public
        givenPolicyHasCustomLogic
        givenPolicyDisableCustomLogicReverts
        givenEnableData(5)
        givenEnabled
        givenDisableData(1, 2)
    {
        // Expect revert
        vm.expectRevert("Disable should revert");

        // Call function
        vm.prank(EMERGENCY);
        policyEnabler.disable(disableData);
    }

    function test_customLogic(
        uint256 value_,
        uint256 anotherValue_
    )
        public
        givenPolicyHasCustomLogic
        givenEnableData(5)
        givenEnabled
        givenDisableData(value_, anotherValue_)
    {
        // Expect event
        vm.expectEmit();
        emit Disabled();

        // Call function
        vm.prank(EMERGENCY);
        policyEnabler.disable(disableData);

        // Assert state
        _assertStateVariables(false, 5, value_, anotherValue_);
    }
}
