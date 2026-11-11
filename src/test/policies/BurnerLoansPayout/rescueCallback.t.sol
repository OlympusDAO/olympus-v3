// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(literal-instead-of-constant)

// Contracts
import {BurnerLoansPayoutCallbackTest} from "./fixtures/BurnerLoansPayoutCallbackTest.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";

contract BurnerLoansPayoutRescueCallbackTest is BurnerLoansPayoutCallbackTest {
    // Scenarios: BLCU-RESCUE-C01.
    function test_givenCaughtNestedRetry_whenRecovered_thenAppliedOnce(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _seedUnrelatedClaims();
        _deferCallbackFee(5);
        _callbackToken.mint(address(_payout), 7);
        bytes32 other = _unrelatedDigest();
        _callbackToken.setTransferBlocked(_treasury(), false);
        _callbackToken.armOutgoing(
            address(_payout),
            _destination,
            abi.encodeCall(_payout.transferPendingPayout, (address(_callbackToken), _treasury())),
            false
        );
        vm.prank(caller_);
        _payout.rescue(address(_callbackToken), _destination);
        _assertCallbackRejected();
        _assertBuckets(address(_callbackToken), _keeper, 5, 0, 0, 5);
        assertEq(_callbackToken.balanceOf(_destination), 7, "Exactly one strict transfer");
        assertEq(_unrelatedDigest(), other, "Other domains preserved");
    }

    // Scenarios: BLCU-RESCUE-C02.
    function test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _seedUnrelatedClaims();
        _deferCallbackFee(5);
        _callbackToken.mint(address(_payout), 7);
        bytes32 beforeCallback = _callbackDigest();
        bytes32 other = _unrelatedDigest();
        _callbackToken.setTransferBlocked(_treasury(), false);
        _callbackToken.armOutgoing(
            address(_payout),
            _destination,
            abi.encodeCall(_payout.transferPendingPayout, (address(_callbackToken), _treasury())),
            true
        );
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(caller_);
        _payout.rescue(address(_callbackToken), _destination);
        assertEq(
            _callbackDigest(),
            beforeCallback,
            "Strict recovery restores balances, debits and indexes"
        );
        assertEq(_unrelatedDigest(), other, "Other custody intact");
    }

    // Scenarios: BLCU-RESCUE-C01.
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

    // Scenarios: BLCU-RESCUE-C02.
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
}

// forge-lint: disable-end(literal-instead-of-constant)
