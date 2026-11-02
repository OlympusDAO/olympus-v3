// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";

// Contracts
import {BurnerLoansPayoutCallbackTest} from "./fixtures/BurnerLoansPayoutCallbackTest.sol";

contract BurnerLoansPayoutCreditFeeCallbackTest is BurnerLoansPayoutCallbackTest {
    // Scenarios: BLCU-CREDIT-FEE-C01.
    function test_givenCaughtRecoveryCallback_whenFeeCredited_thenSingleDelivery()
        public
        givenPendingBuckets
    {
        _seedUnrelatedClaims();
        _deferCallbackFee(5);
        bytes32 other = _unrelatedDigest();
        _callbackToken.setTransferBlocked(_treasury(), false);
        _callbackToken.mint(address(_payout), 19);
        _callbackToken.armOutgoing(
            address(_payout),
            _treasury(),
            abi.encodeCall(_payout.transferPendingPayout, (address(_callbackToken), _treasury())),
            false
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_callbackToken), 7);
        _assertCallbackRejected();
        _assertBuckets(address(_callbackToken), _keeper, 0, 0, 0, 0);
        assertEq(_callbackToken.balanceOf(_treasury()), 12, "Old 5 plus new 7 paid once");
        assertEq(_unrelatedDigest(), other, "Other tokens, keepers and retired Payout untouched");
    }

    // Scenarios: BLCU-CREDIT-FEE-C02.
    function test_givenPropagatedRecoveryCallback_whenFeeCredited_thenDeferredAndRetryable()
        public
        givenPendingBuckets
    {
        _seedUnrelatedClaims();
        _deferCallbackFee(5);
        bytes32 other = _unrelatedDigest();
        _callbackToken.setTransferBlocked(_treasury(), false);
        _callbackToken.mint(address(_payout), 19);
        bytes memory nested = abi.encodeCall(
            _payout.transferPendingPayout,
            (address(_callbackToken), _treasury())
        );
        _callbackToken.armOutgoing(address(_payout), _treasury(), nested, true);
        vm.expectCall(address(_payout), nested, 3);
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutDeferred(
            address(_callbackToken),
            _treasury(),
            IBurnerLoansPayout.PayoutKind.Fee,
            12
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_callbackToken), 7);
        _assertBuckets(address(_callbackToken), _keeper, 12, 0, 0, 12);
        assertEq(_callbackToken.balanceOf(_treasury()), 0, "Rejected delivery leaves fee owed");
        assertEq(
            _callbackToken.balanceOf(address(_payout)),
            24,
            "Fee and donated excess stay in custody"
        );
        _callbackToken.disarm();
        assertEq(
            _payout.transferPendingPayout(address(_callbackToken), _treasury()),
            12,
            "Callback-free retry pays full obligation"
        );
        assertEq(
            _payout.transferPendingPayout(address(_callbackToken), _treasury()),
            0,
            "No duplicate payment"
        );
        assertEq(_unrelatedDigest(), other, "Other ledgers isolated");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
