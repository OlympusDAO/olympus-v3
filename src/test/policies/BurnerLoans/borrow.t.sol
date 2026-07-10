// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansBorrowTest is BurnerLoansTest {
    address internal operator;

    function setUp() public override {
        super.setUp();
        operator = makeAddr("operator");
        _addDefaultUsdsAsset();
    }

    // Condition tree:
    // - Caller: owner (`alice`)
    // - Authorization state: owner acts on own account
    // - Parameters: asset is configured, recipient is owner, authorization deadline is unused
    // - Expected branch: authorization and recipient checks pass, then placeholder reverts
    function test_borrow_givenOwnerCaller_reachesPlaceholder() public {
        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_NotImplemented.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, alice, 0);
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: no authorization from owner to operator
    // - Parameters: onBehalfOf is owner, recipient is operator
    // - Expected branch: authorization check reverts before placeholder logic
    function test_borrow_givenUnauthorizedOperator_reverts() public {
        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, operator, 0);
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: owner has authorized operator through a future deadline
    // - Parameters: onBehalfOf is owner, recipient is operator
    // - Expected branch: authorization and recipient checks pass, then placeholder reverts
    function test_borrow_givenAuthorizedOperatorWithOperatorRecipient_reachesPlaceholder() public {
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));

        vm.prank(operator);
        vm.expectRevert(IBurnerLoans.BurnerLoans_NotImplemented.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, operator, 0);
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: owner authorization exists but block timestamp is after deadline
    // - Parameters: onBehalfOf is owner, recipient is operator
    // - Expected branch: authorization check reverts before placeholder logic
    function test_borrow_givenExpiredAuthorization_reverts() public {
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1));
        vm.warp(block.timestamp + 2);

        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, operator, 0);
    }

    // Condition tree:
    // - Caller: owner (`alice`)
    // - Authorization state: owner acts on own account
    // - Parameters: recipient is zero address
    // - Expected branch: recipient validation reverts before placeholder logic
    function test_borrow_givenZeroRecipient_reverts() public {
        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, address(0), 0);
    }

    // Condition tree:
    // - Caller: fuzzed caller that is neither owner nor authorized operator
    // - Authorization state: owner has authorized only `operator`
    // - Parameters: onBehalfOf is owner, recipient is fuzzed caller
    // - Expected branch: authorization check reverts for every non-owner, non-operator caller
    function test_borrow_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != alice);
        vm.assume(caller_ != operator);

        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));

        vm.prank(caller_);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.borrow(address(usds), 1e9, alice, caller_, 0);
    }
}
