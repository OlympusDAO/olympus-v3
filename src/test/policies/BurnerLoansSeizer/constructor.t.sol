// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerConstructorTest is BurnerLoansSeizerTest {
    function test_givenZeroBurnerLoans_reverts() public {
        vm.expectRevert(IBurnerLoansSeizer.BurnerLoansSeizer_ZeroAddress.selector);
        new BurnerLoansSeizer(kernel, address(0), 10, 5);
    }

    function test_givenInvalidInitialLimits_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizer.BurnerLoansSeizer_InvalidScanLimits.selector,
                4,
                5
            )
        );
        new BurnerLoansSeizer(kernel, address(target), 4, 5);
    }
}
