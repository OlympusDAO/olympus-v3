// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {BurnerLoansAuthorizationIntegrationTest} from "./authorizationLifecycleTest.sol";

contract BurnerLoansCoreExtendAuthorizationTest is BurnerLoansAuthorizationIntegrationTest {
    // Scenarios: BLCORE-SETTLE-EXTEND-N90.
    function test_givenDelegatedGrant_whenActualMaturityExceedsLimit_reverts() public {
        _deposit(2000e6);
        _borrow(100e9);
        uint48 limit = _rawPosition().maturity + 1 days;
        _acceptBounded(_boundedGrant(8, 0, 0, 0, limit));
        IBurnerLoansCore.AuthorizationContext memory original = _delegatedContext(8);
        bytes32 before = _ledger();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        vm.prank(address(_debt));
        _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _recipient,
                maturity: limit + 1,
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            _recipient,
            original
        );
        assertEq(
            _ledger(),
            before,
            "Maturity bound failure restores canonical debt and fee accounting"
        );
    }

    // Scenarios: BLCORE-SETTLE-EXTEND-P90.
    function test_givenDelegatedGrant_whenActualMaturityEqualsLimit() public {
        _deposit(2000e6);
        _borrow(100e9);
        uint48 limit = _rawPosition().maturity + 1 days;
        _acceptBounded(_boundedGrant(8, 0, 0, 0, limit));
        IBurnerLoansCore.AuthorizationContext memory original = _delegatedContext(8);
        vm.prank(address(_debt));
        uint48 maturity = _core.settleExtend(
            IBurnerLoansCore.ExtendRequest({
                asset: address(_asset),
                borrower: _borrower,
                payer: _recipient,
                maturity: limit,
                protocolFee: 0,
                referrer: address(0),
                referralFee: 0
            }),
            _recipient,
            original
        );
        assertEq(maturity, limit, "Extend enforces an inclusive absolute timestamp bound");
    }
}
// forge-lint: disable-end(unused-return)
