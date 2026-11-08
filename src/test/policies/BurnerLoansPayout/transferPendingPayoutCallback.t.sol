// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// Expected-revert calls and repeat-configuration probes discard their return values.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Contracts
import {BurnerLoansPayoutCallbackTest} from "./fixtures/BurnerLoansPayoutCallbackTest.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";

contract BurnerLoansPayoutTransferPendingPayoutCallbackTest is BurnerLoansPayoutCallbackTest {
    // Scenarios: BLCUTRY-C05.
    function test_givenReferralPending_whenCaughtCallbackRetries() public {
        _callbackToken.setTransferBlocked(_keeper, true);
        _callbackToken.mint(address(_payout), 25);
        vm.prank(address(_core));
        _payout.creditFee(address(_callbackToken), 0, _keeper, 25);
        _callbackToken.setTransferBlocked(_keeper, false);
        _callbackToken.armOutgoing(
            address(_payout),
            _keeper,
            abi.encodeCall(_payout.transferPendingPayout, (address(_callbackToken), _keeper)),
            false
        );
        assertEq(
            _payout.transferPendingPayout(address(_callbackToken), _keeper),
            25,
            "Outer referral retry pays once"
        );
        _assertCallbackRejected();
        _assertReferral(address(_callbackToken), _keeper, 0);
        _assertBuckets(address(_callbackToken), _keeper, 0, 0, 0, 0);
    }

    // Scenarios: BLCUTRY-C07.
    function test_givenReferralPending_whenPropagatedCallbackRetries() public {
        _callbackToken.setTransferBlocked(_keeper, true);
        _callbackToken.mint(address(_payout), 25);
        vm.prank(address(_core));
        _payout.creditFee(address(_callbackToken), 0, _keeper, 25);
        _callbackToken.setTransferBlocked(_keeper, false);
        bytes memory nested = abi.encodeCall(
            _payout.transferPendingPayout,
            (address(_callbackToken), _keeper)
        );
        _callbackToken.armOutgoing(address(_payout), _keeper, nested, true);
        vm.expectCall(address(_payout), nested, 2);
        assertEq(
            _payout.transferPendingPayout(address(_callbackToken), _keeper),
            0,
            "Propagated callback defers entire reward"
        );
        _assertReferral(address(_callbackToken), _keeper, 25);
        _assertBuckets(address(_callbackToken), _keeper, 0, 0, 0, 25);
        assertEq(_callbackToken.balanceOf(address(_payout)), 25, "Retry failure preserves backing");
    }

    // Scenarios: BLCUTRY-C03.
    function test_givenCaughtNestedRetry_whenRetried_thenOnePayment() public givenPendingBuckets {
        _seedUnrelatedClaims();
        _deferCallbackFee(10);
        _callbackToken.mint(address(_payout), 10);
        bytes32 other = _unrelatedDigest();
        _callbackToken.setTransferBlocked(_treasury(), false);
        _callbackToken.armOutgoing(
            address(_payout),
            _treasury(),
            abi.encodeCall(_payout.transferPendingPayout, (address(_callbackToken), _treasury())),
            false
        );
        assertEq(
            _payout.transferPendingPayout(address(_callbackToken), _treasury()),
            10,
            "Outer retry pays once"
        );
        _assertCallbackRejected();
        _assertBuckets(address(_callbackToken), _keeper, 0, 0, 0, 0);
        assertEq(_callbackToken.balanceOf(_treasury()), 10, "No second payout");
        assertEq(_unrelatedDigest(), other, "Other domains intact");
    }

    // Scenarios: BLCUTRY-C04.
    function test_givenPropagatedNestedRetry_whenRetried_thenPendingRetained()
        public
        givenPendingBuckets
    {
        _seedUnrelatedClaims();
        _deferCallbackFee(10);
        _callbackToken.mint(address(_payout), 10);
        bytes32 beforeCallback = _callbackDigest();
        bytes32 other = _unrelatedDigest();
        _callbackToken.setTransferBlocked(_treasury(), false);
        bytes memory nested = abi.encodeCall(
            _payout.transferPendingPayout,
            (address(_callbackToken), _treasury())
        );
        _callbackToken.armOutgoing(address(_payout), _treasury(), nested, true);
        vm.expectCall(address(_payout), nested, 2);
        assertEq(
            _payout.transferPendingPayout(address(_callbackToken), _treasury()),
            0,
            "Failed optional transfer returns zero"
        );
        assertEq(_callbackDigest(), beforeCallback, "Whole entitlement stays backed and indexed");
        assertEq(_unrelatedDigest(), other, "Other custody intact");
    }

    // Scenarios: BLCUTRY-C01.
    function test_givenCaughtIncomingCallback_whenCoreSettles_thenNoPrematureRecovery()
        public
        givenPendingBuckets
    {
        _prepareIncoming(
            abi.encodeCall(_payout.transferPendingPayout, (address(_token), _keeper)),
            false
        );
        bytes32 state = _ledgerDigest();
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_callbackToken), 100e18, _borrower);
        _assertCallbackRejected();
        assertEq(_ledgerDigest(), state, "Incoming receipt blocks early recovery");
        assertEq(
            _lens.getPosition(address(_callbackToken), _borrower).depositedCollateral,
            100e18,
            "One outer deposit"
        );
        assertEq(_callbackToken.balanceOf(_borrower), 0, "Receipt collected once");
    }

    // Scenarios: BLCUTRY-C02.
    function test_givenPropagatedIncomingCallback_whenCoreSettles_thenOuterRollback()
        public
        givenPendingBuckets
    {
        _prepareIncoming(
            abi.encodeCall(_payout.transferPendingPayout, (address(_token), _keeper)),
            true
        );
        bytes32 state = _ledgerDigest();
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_callbackToken), 100e18, _borrower);
        assertEq(_ledgerDigest(), state, "Payout accounting untouched");
        assertEq(
            _lens.getPosition(address(_callbackToken), _borrower).depositedCollateral,
            0,
            "No failed receipt credited"
        );
        assertEq(_callbackToken.balanceOf(_borrower), 100e18, "Receipt transfer rolled back");
    }

    function test_givenPreviousPayoutCallback_whenNewPayoutRetried_thenIndependentDomainsSettle()
        public
    {
        ReentrantPayoutToken token = new ReentrantPayoutToken();
        token.setTransferBlocked(_treasury(), true);
        token.mint(address(_payout), 5);
        vm.prank(address(_core));
        _payout.creditFee(address(token), 5, address(0), 0);
        token.mint(address(_otherPayout), 7);
        vm.prank(address(_core));
        _otherPayout.creditFee(address(token), 7, address(0), 0);
        token.setTransferBlocked(_treasury(), false);
        token.setCallbackFrom(
            address(_otherPayout),
            address(_payout),
            abi.encodeCall(_payout.transferPendingPayout, (address(token), _treasury()))
        );
        token.setCallbackPhases(true, false);
        assertEq(
            _otherPayout.transferPendingPayout(address(token), _treasury()),
            7,
            "Previous instance pays only its own obligation"
        );
        assertTrue(token.callbackSucceeded(), "Other instance has an independent guard and ledger");
        _assertBuckets(address(token), _keeper, 0, 0, 0, 0);
        (, , , , uint256 oldTotal) = _otherPayout.pendingAmounts(address(token));
        assertEq(oldTotal, 0, "Previous instance settles independently");
        assertEq(token.balanceOf(_treasury()), 12, "Both distinct entitlements paid once");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
