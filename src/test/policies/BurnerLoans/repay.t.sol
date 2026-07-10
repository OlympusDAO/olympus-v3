// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansRepayTest is BurnerLoansTest {
    address internal operator;

    function setUp() public override {
        super.setUp();
        operator = makeAddr("operator");
        _addDefaultUsdsAsset();
    }

    // Condition tree:
    // - Caller: any payer (`operator`)
    // - Authorization state: repayment does not require borrower authorization
    // - Parameters: asset is configured, borrower is owner
    // - Expected branch: no authorization check blocks repayment, then placeholder reverts
    function test_repay_givenDifferentCaller_reachesPlaceholder() public {
        vm.prank(operator);
        vm.expectRevert(IBurnerLoans.BurnerLoans_NotImplemented.selector);
        burnerLoans.repay(address(usds), 1e9, alice);
    }
}
