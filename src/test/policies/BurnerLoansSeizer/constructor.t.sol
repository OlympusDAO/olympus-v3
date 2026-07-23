// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerConstructorTest is BurnerLoansSeizerTest {
    // constructor
    // given valid parameters
    //  when the seizer is deployed
    //   then it stores its immutable target and initial scan state
    function test_givenValidParameters_setsInitialState() public view {
        assertEq(seizer.burnerLoans(), address(target), "burner loans");
        assertEq(seizer.maxBorrowersToCheck(), 10, "borrowers to check");
        assertEq(seizer.maxBorrowersToSeize(), 5, "borrowers to seize");
        assertEq(seizer.nextAssetIndex(), 0, "next asset index");
        assertEq(seizer.getAssets().length, 0, "managed assets");
    }

    // constructor
    // given zero burner loans
    //  when constructor is called
    //   then it reverts
    function test_givenZeroBurnerLoans_reverts() public {
        vm.expectRevert(IBurnerLoansSeizer.BurnerLoansSeizer_ZeroAddress.selector);
        new BurnerLoansSeizer(kernel, address(0), 10, 5);
    }

    // constructor
    // given invalid initial limits
    //  when constructor is called
    //   then it reverts
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
