// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {PolicyEnablerTest} from "./PolicyEnablerTest.sol";

contract PolicyEnablerOnlyEnabledTest is PolicyEnablerTest {
    // given the policy is disabled
    //  [X] it reverts
    // [X] it does not revert

    function test_policyDisabled_reverts() public {
        // Expect revert
        vm.expectRevert(PolicyEnabler.NotEnabled.selector);

        // Call function
        policyEnabler.requiresEnabled();
    }

    function test_policyEnabled() public givenEnabled {
        // Call function
        assertEq(policyEnabler.requiresEnabled(), true, "Policy should be enabled");
    }
}
