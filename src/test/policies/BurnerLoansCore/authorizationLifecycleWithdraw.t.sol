// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {BurnerLoansAuthorizationIntegrationTest} from "./authorizationLifecycleTest.sol";

contract BurnerLoansCoreWithdrawAuthorizationTest is BurnerLoansAuthorizationIntegrationTest {
    // Scenarios: BLCORE-SETTLE-WITHDRAW-N90.
    function test_givenDelegatedGrant_whenRemainingCollateralBelowFloor_reverts() public {
        _deposit(1000);
        _acceptBounded(_boundedGrant(4, 0, 0, 901, 0));
        IBurnerLoansCore.AuthorizationContext memory original = _delegatedContext(4);
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        vm.prank(address(_collateral));
        _core.settleWithdraw(
            IBurnerLoansCore.WithdrawRequest({
                asset: address(_asset),
                amount: 100,
                borrower: _borrower,
                recipient: _recipient
            }),
            _recipient,
            original
        );
        assertEq(
            _ledger(),
            before,
            "Floor failure restores custody output and canonical collateral"
        );
    }

    // Scenarios: BLCORE-SETTLE-WITHDRAW-P90.
    function test_givenDelegatedGrant_whenRemainingCollateralEqualsFloor() public {
        _deposit(1000);
        _acceptBounded(_boundedGrant(4, 0, 0, 900, 0));
        IBurnerLoansCore.AuthorizationContext memory original = _delegatedContext(4);
        vm.prank(address(_collateral));
        (, , uint128 remaining) = _core.settleWithdraw(
            IBurnerLoansCore.WithdrawRequest({
                asset: address(_asset),
                amount: 100,
                borrower: _borrower,
                recipient: _recipient
            }),
            _recipient,
            original
        );
        assertEq(remaining, 900, "1000 minus 100 equals the inclusive 900 raw-unit floor");
        assertEq(
            _asset.balanceOf(_recipient),
            100,
            "Authorized recipient receives withdrawal output"
        );
    }
}
// forge-lint: disable-end(unused-return)
