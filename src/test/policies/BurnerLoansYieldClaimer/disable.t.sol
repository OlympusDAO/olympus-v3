// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerDisableTest is BurnerLoansYieldClaimerTest {
    function test_givenAdmin_disables() public {
        vm.prank(admin);
        claimer.disable("");

        assertFalse(claimer.isEnabled(), "disabled");
    }

    function test_givenEmergency_disables() public {
        vm.prank(_emergency);
        claimer.disable("");

        assertFalse(claimer.isEnabled(), "disabled");
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != _emergency);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        claimer.disable("");
    }

    function test_givenAlreadyDisabled_reverts() public {
        vm.prank(_emergency);
        claimer.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_emergency);
        claimer.disable("");
    }
}
