// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";

// Contracts
import {Actions} from "src/Kernel.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerEnableTest is BurnerLoansSeizerTest {
    function test_givenBurnerLoansActive_enables() public {
        vm.startPrank(admin);
        seizer.disable("");
        seizer.enable("");
        vm.stopPrank();

        assertTrue(seizer.isEnabled(), "seizer enabled");
    }

    function test_givenBurnerLoansInactive_reverts() public {
        vm.startPrank(admin);
        seizer.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(target));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizer.BurnerLoansSeizer_InvalidBurnerLoans.selector,
                address(target)
            )
        );
        seizer.enable("");
        vm.stopPrank();
    }
}
