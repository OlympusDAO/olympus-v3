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
        address treasury = _treasury();
        _seedUnrelatedClaims();
        _deferCallbackFee(5);
        _deferCallbackSeizure(7, 0);
        _callbackToken.mint(address(_payout), 11);
        vm.prank(address(_core));
        _payout.creditFee(address(_callbackToken), 0, treasury, 11);
        _callbackToken.setTransferBlocked(_keeper, false);
        bytes32 other = _unrelatedDigest();
        _callbackToken.armOutgoing(
            address(_payout),
            _destination,
            abi.encodeCall(_payout.transferPendingPayout, (address(_callbackToken), _keeper)),
            false
        );
        vm.prank(caller_);
        _payout.rescuePendingPayout(address(_callbackToken), treasury, _destination, 16);
        _assertCallbackRejected();
        _assertReferral(address(_callbackToken), treasury, 0);
        _assertBuckets(address(_callbackToken), _keeper, 0, 0, 7, 7);
        assertEq(
            _callbackToken.balanceOf(_destination),
            16,
            "Exactly one strict transfer for protocol5 plus referral11"
        );
        assertEq(_unrelatedDigest(), other, "Other domains preserved");
    }

    // Scenarios: BLCU-PENDING-RESCUE-C02.
    function test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        address treasury = _treasury();
        _seedUnrelatedClaims();
        _deferCallbackFee(5);
        _deferCallbackSeizure(7, 0);
        _callbackToken.mint(address(_payout), 11);
        vm.prank(address(_core));
        _payout.creditFee(address(_callbackToken), 0, treasury, 11);
        _callbackToken.setTransferBlocked(_keeper, false);
        bytes32 beforeCallback = _callbackDigest();
        bytes32 other = _unrelatedDigest();
        _callbackToken.armOutgoing(
            address(_payout),
            _destination,
            abi.encodeCall(_payout.transferPendingPayout, (address(_callbackToken), _keeper)),
            true
        );
        address recipient = treasury;
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(caller_);
        _payout.rescuePendingPayout(address(_callbackToken), recipient, _destination, 16);
        _assertReferral(address(_callbackToken), treasury, 11);
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

    // Scenarios: BLCU-PENDING-RESCUE-C03.
    function test_givenPartialRecovery_whenTokenReadsAccounting_thenDebitAlreadyVisible() public {
        ReentrantPayoutToken token = new ReentrantPayoutToken();
        token.setTransferBlocked(_treasury(), true);
        token.mint(address(_payout), 100);
        address treasury = _treasury();
        vm.prank(address(_core));
        _payout.creditFee(address(token), 10, treasury, 40);
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
        assertEq(observer.total(), 95, "Visible aggregate debit");
        assertEq(observer.referral(), 40, "Partial keeper debit preserves the referral bucket");
        assertEq(observer.totalReferral(), 40, "Aggregate referral reserve remains visible");
        assertTrue(observer.referrerIndexed(), "Nonempty referral remains indexed during transfer");
        assertEq(observer.tokenIndexed(), true, "Visible token membership");
        assertEq(observer.keeperIndexed(), true, "Visible keeper membership");
        assertEq(token.balanceOf(_destination), 5, "One outer strict transfer");
    }

    // Scenarios: BLCU-PENDING-RESCUE-C03.
    function test_givenRecoveryIntoReferral_whenTokenReadsAccounting(uint256 amount_) public {
        amount_ = bound(amount_, 61, 100);
        ReentrantPayoutToken token = new ReentrantPayoutToken();
        token.setTransferBlocked(_treasury(), true);
        token.mint(address(_payout), 100);
        address treasury = _treasury();
        vm.prank(address(_core));
        _payout.creditFee(address(token), 10, treasury, 40);
        vm.prank(address(_core));
        _payout.creditSeizure(address(token), treasury, 30, 20);
        PayoutReadObserver observer = new PayoutReadObserver(_subject);
        token.setCallbackFrom(
            address(_payout),
            address(observer),
            abi.encodeCall(observer.observe, (address(token), _treasury()))
        );
        token.setCallbackPhases(true, false);
        _payout.rescuePendingPayout(address(token), _treasury(), _destination, amount_);
        assertTrue(token.callbackSucceeded(), "Accounting remains readable during transfer");
        assertEq(observer.fee(), 0, "Visible fee debit");
        assertEq(observer.seized(), 0, "Visible seized debit");
        assertEq(observer.reward(), 0, "Visible keeper debit");
        assertEq(observer.total(), 100 - amount_, "Visible aggregate debit");
        assertEq(observer.referral(), 100 - amount_, "Visible original referral debit");
        assertEq(observer.totalReferral(), 100 - amount_, "Visible aggregate referral debit");
        assertEq(observer.totalKeeperReward(), 0, "Keeper aggregate is fully debited");
        assertEq(observer.tokenIndexed(), amount_ != 100, "Visible token membership");
        assertEq(
            observer.referrerIndexed(),
            amount_ != 100,
            "Referral index updates before transfer"
        );
        assertEq(observer.keeperIndexed(), false, "Visible keeper membership");
        assertEq(token.balanceOf(_destination), amount_, "One outer strict transfer");
    }

    // Scenarios: BLCU-PENDING-RESCUE-C03.
    function test_givenRecoveryIntoReferral_whenReadBoundarySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenRecoveryIntoReferral_whenTokenReadsAccounting(61);
        _restore(checkpoint);
        test_givenRecoveryIntoReferral_whenTokenReadsAccounting(99);
        _restore(checkpoint);
        test_givenRecoveryIntoReferral_whenTokenReadsAccounting(100);
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
