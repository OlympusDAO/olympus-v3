// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {PolicyEnablerTest} from "./PolicyEnablerTest.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract PolicyEnablerOnlyDisabledTest is PolicyEnablerTest {
    // given the policy is enabled
    //  [X] it reverts
    // [X] it does not revert

    function test_policyEnabled_reverts() public givenEnabled {
        // Expect revert
        vm.expectRevert(IEnabler.NotDisabled.selector);

        // Call function
        policyEnabler.requiresDisabled();
    }

    function test_policyDisabled() public view {
        // Call function
        assertEq(policyEnabler.requiresDisabled(), true, "Policy should be disabled");
    }
}
