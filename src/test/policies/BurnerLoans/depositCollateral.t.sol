// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansDepositCollateralTest is BurnerLoansTest {
    address internal operator;

    function setUp() public override {
        super.setUp();
        operator = makeAddr("operator");
        _addDefaultUsdsAsset();
    }

    // Condition tree:
    // - Caller: owner (`alice`)
    // - Authorization state: owner acts on own account
    // - Parameters: asset is configured, onBehalfOf is owner
    // - Expected branch: authorization check passes, then placeholder reverts
    function test_depositCollateral_givenOwnerCaller_reachesPlaceholder() public {
        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_NotImplemented.selector);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: no authorization from owner to operator
    // - Parameters: asset is configured, onBehalfOf is owner
    // - Expected branch: authorization check reverts before placeholder logic
    function test_depositCollateral_givenUnauthorizedOperator_reverts() public {
        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: owner has authorized operator through a future deadline
    // - Parameters: asset is configured, onBehalfOf is owner
    // - Expected branch: authorization check passes, then placeholder reverts
    function test_depositCollateral_givenAuthorizedOperator_reachesPlaceholder() public {
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));

        vm.prank(operator);
        vm.expectRevert(IBurnerLoans.BurnerLoans_NotImplemented.selector);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);
    }

    // Condition tree:
    // - Caller: fuzzed caller that is neither owner nor authorized operator
    // - Authorization state: owner has authorized only `operator`
    // - Parameters: asset is configured, onBehalfOf is owner
    // - Expected branch: authorization check reverts for every non-owner, non-operator caller
    function test_depositCollateral_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != alice);
        vm.assume(caller_ != operator);

        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));

        vm.prank(caller_);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);
    }
}
