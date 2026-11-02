// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(literal-instead-of-constant)

// Contracts
import {BurnerLoansPayoutCallbackTest} from "./fixtures/BurnerLoansPayoutCallbackTest.sol";
import {PayoutReadObserver} from "./fixtures/PayoutReadObserver.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";

contract BurnerLoansPayoutRescuePendingPayoutCallbackTest is BurnerLoansPayoutCallbackTest {
    // Scenarios: BLCU-PENDING-RESCUE-C01.
    function test_givenCaughtNestedRetry_whenRecovered_thenAppliedOnce(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _seedUnrelatedClaims();
        _deferCallbackFee(5);
        _deferCallbackSeizure(7, 0);
        _callbackToken.setTransferBlocked(_keeper, false);
        bytes32 other = _unrelatedDigest();
        _callbackToken.armOutgoing(
            address(_payout),
            _destination,
            abi.encodeCall(_payout.transferPendingPayout, (address(_callbackToken), _keeper)),
            false
        );
        vm.prank(caller_);
        _payout.rescuePendingPayout(address(_callbackToken), _treasury(), _destination, 5);
        _assertCallbackRejected();
        _assertBuckets(address(_callbackToken), _keeper, 0, 0, 7, 7);
        assertEq(_callbackToken.balanceOf(_destination), 5, "Exactly one strict transfer");
        assertEq(_unrelatedDigest(), other, "Other domains preserved");
    }

    // Scenarios: BLCU-PENDING-RESCUE-C02.
    function test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _seedUnrelatedClaims();
        _deferCallbackFee(5);
        _deferCallbackSeizure(7, 0);
        _callbackToken.setTransferBlocked(_keeper, false);
        bytes32 beforeCallback = _callbackDigest();
        bytes32 other = _unrelatedDigest();
        _callbackToken.armOutgoing(
            address(_payout),
            _destination,
            abi.encodeCall(_payout.transferPendingPayout, (address(_callbackToken), _keeper)),
            true
        );
        address recipient = _treasury();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(caller_);
        _payout.rescuePendingPayout(address(_callbackToken), recipient, _destination, 5);
        assertEq(
            _callbackDigest(),
            beforeCallback,
            "Strict recovery restores balances, debits and indexes"
        );
        assertEq(_unrelatedDigest(), other, "Other custody intact");
    }

    // Scenarios: BLCU-PENDING-RESCUE-C01.
    function test_givenCaughtNestedRetry_givenEachRecoveryRole_whenRecovered_thenAppliedOnce()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenCaughtNestedRetry_whenRecovered_thenAppliedOnce(address(0xabc1), false, false);
        _restore(checkpoint);
        test_givenCaughtNestedRetry_whenRecovered_thenAppliedOnce(address(0xabc2), true, false);
        _restore(checkpoint);
        test_givenCaughtNestedRetry_whenRecovered_thenAppliedOnce(address(0xabc3), false, true);
        _restore(checkpoint);
    }

    // Scenarios: BLCU-PENDING-RESCUE-C02.
    function test_givenPropagatedNestedRetry_givenEachRecoveryRole_whenRecovered_thenCompleteRollback()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback(
            address(0xabc1),
            false,
            false
        );
        _restore(checkpoint);
        test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback(
            address(0xabc2),
            true,
            false
        );
        _restore(checkpoint);
        test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback(
            address(0xabc3),
            false,
            true
        );
        _restore(checkpoint);
    }

    function test_givenPartialRecovery_whenTokenReadsAccounting_thenDebitAlreadyVisible() public {
        ReentrantPayoutToken token = new ReentrantPayoutToken();
        token.setTransferBlocked(_treasury(), true);
        token.mint(address(_payout), 60);
        address treasury = _treasury();
        vm.prank(address(_core));
        _payout.creditFee(address(token), 10);
        vm.prank(address(_core));
        _payout.creditSeizure(address(token), treasury, 30, 20);
        PayoutReadObserver observer = new PayoutReadObserver(_subject);
        token.setCallbackFrom(
            address(_payout),
            address(observer),
            abi.encodeCall(observer.observe, (address(token), _treasury()))
        );
        token.setCallbackPhases(true, false);
        _payout.rescuePendingPayout(address(token), _treasury(), _destination, 5);
        assertTrue(token.callbackSucceeded(), "Accounting remains readable during transfer");
        assertEq(observer.fee(), 10, "Visible fee debit");
        assertEq(observer.seized(), 20, "Visible seized debit");
        assertEq(observer.reward(), 25, "Visible keeper debit");
        assertEq(observer.total(), 55, "Visible aggregate debit");
        assertEq(observer.tokenIndexed(), true, "Visible token membership");
        assertEq(observer.keeperIndexed(), true, "Visible keeper membership");
        assertEq(token.balanceOf(_destination), 5, "One outer strict transfer");
    }

    function test_givenFullRecovery_whenTokenReadsAccounting_thenDebitAlreadyVisible() public {
        ReentrantPayoutToken token = new ReentrantPayoutToken();
        token.setTransferBlocked(_treasury(), true);
        token.mint(address(_payout), 60);
        address treasury = _treasury();
        vm.prank(address(_core));
        _payout.creditFee(address(token), 10);
        vm.prank(address(_core));
        _payout.creditSeizure(address(token), treasury, 30, 20);
        PayoutReadObserver observer = new PayoutReadObserver(_subject);
        token.setCallbackFrom(
            address(_payout),
            address(observer),
            abi.encodeCall(observer.observe, (address(token), _treasury()))
        );
        token.setCallbackPhases(true, false);
        _payout.rescuePendingPayout(address(token), _treasury(), _destination, 60);
        assertTrue(token.callbackSucceeded(), "Accounting remains readable during transfer");
        assertEq(observer.fee(), 0, "Visible fee debit");
        assertEq(observer.seized(), 0, "Visible seized debit");
        assertEq(observer.reward(), 0, "Visible keeper debit");
        assertEq(observer.total(), 0, "Visible aggregate debit");
        assertEq(observer.tokenIndexed(), false, "Visible token membership");
        assertEq(observer.keeperIndexed(), false, "Visible keeper membership");
        assertEq(token.balanceOf(_destination), 60, "One outer strict transfer");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
