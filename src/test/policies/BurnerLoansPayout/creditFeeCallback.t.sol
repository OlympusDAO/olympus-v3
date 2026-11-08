// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";

// Contracts
import {BurnerLoansPayoutCallbackTest} from "./fixtures/BurnerLoansPayoutCallbackTest.sol";
import {PayoutReadObserver} from "./fixtures/PayoutReadObserver.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";

contract BurnerLoansPayoutCreditFeeCallbackTest is BurnerLoansPayoutCallbackTest {
    // Scenarios: BLCU-CREDIT-FEE-P08.
    function test_whenFirstTransferObservesBothReservedComponents() public {
        ReentrantPayoutToken token = new ReentrantPayoutToken();
        PayoutReadObserver observer = new PayoutReadObserver(_subject);
        token.setCallbackFrom(
            address(_payout),
            address(observer),
            abi.encodeCall(observer.observe, (address(token), _keeper))
        );
        token.setCallbackTransferRecipient(_treasury());
        token.setCallbackPhases(true, false);
        token.mint(address(_payout), 101);
        vm.prank(address(_core));
        _payout.creditFee(address(token), 76, _keeper, 25);
        assertTrue(token.callbackSucceeded(), "Read-only callback observes live reserve state");
        assertEq(observer.fee(), 76, "Protocol allocation reserved before first transfer");
        assertEq(observer.referral(), 25, "Referral allocation reserved before first transfer");
        assertEq(
            observer.totalReferral(),
            25,
            "Aggregate referral reserve established before delivery"
        );
        assertEq(
            observer.totalKeeperReward(),
            0,
            "Keeper reserve remains separate during delivery"
        );
        assertEq(
            observer.total(),
            101,
            "Both components count in aggregate reserve during delivery"
        );
        assertEq(token.balanceOf(_keeper), 25, "Recipient still paid after observation");
    }

    // Scenarios: BLCU-CREDIT-FEE-C03.
    function test_givenCaughtReferralCallback_whenFeeCredited() public {
        _callbackToken.mint(address(_payout), 101);
        _callbackToken.armOutgoing(
            address(_payout),
            _keeper,
            abi.encodeCall(_payout.transferPendingPayout, (address(_callbackToken), _keeper)),
            false
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_callbackToken), 76, _keeper, 25);
        _assertCallbackRejected();
        _assertReferral(address(_callbackToken), _keeper, 0);
        _assertBuckets(address(_callbackToken), _keeper, 0, 0, 0, 0);
        assertEq(
            _callbackToken.balanceOf(_keeper),
            25,
            "Caught callback pays original reward once"
        );
        assertEq(
            _callbackToken.balanceOf(_treasury()),
            76,
            "Protocol component remains independent"
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-C04.
    function test_givenPropagatedReferralCallback_whenFeeCredited() public {
        _callbackToken.mint(address(_payout), 101);
        bytes memory nested = abi.encodeCall(
            _payout.transferPendingPayout,
            (address(_callbackToken), _keeper)
        );
        _callbackToken.armOutgoing(address(_payout), _keeper, nested, true);
        vm.expectCall(address(_payout), nested, 1);
        vm.prank(address(_core));
        _payout.creditFee(address(_callbackToken), 76, _keeper, 25);
        _assertReferral(address(_callbackToken), _keeper, 25);
        _assertBuckets(address(_callbackToken), _keeper, 0, 0, 0, 25);
        assertEq(_callbackToken.balanceOf(_keeper), 0, "Propagated subcall rolled back delivery");
        assertEq(
            _callbackToken.balanceOf(address(_payout)),
            25,
            "Entire deferred referral stays backed"
        );
        assertEq(
            _callbackToken.balanceOf(_treasury()),
            76,
            "Optional referral failure preserves protocol payment"
        );
    }

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
        _payout.creditFee(address(_callbackToken), 7, address(0), 0);
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
        _payout.creditFee(address(_callbackToken), 7, address(0), 0);
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
