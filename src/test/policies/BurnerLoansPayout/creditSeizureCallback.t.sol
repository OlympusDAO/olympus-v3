// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(literal-instead-of-constant)

// Contracts
import {BurnerLoansPayoutCallbackTest} from "./fixtures/BurnerLoansPayoutCallbackTest.sol";

contract BurnerLoansPayoutCreditSeizureCallbackTest is BurnerLoansPayoutCallbackTest {
    // Scenarios: BLCU-CREDIT-SEIZURE-C01.
    function test_givenCaughtCallback_whenKeeperOrTreasuryPaid_thenBothAllocationsOnce(
        bool keeperPhase_
    ) public givenPendingBuckets {
        _seedUnrelatedClaims();
        _deferCallbackSeizure(3, 4);
        bytes32 other = _unrelatedDigest();
        _callbackToken.setTransferBlocked(_keeper, false);
        _callbackToken.setTransferBlocked(_treasury(), false);
        _callbackToken.mint(address(_payout), 43);
        address recipient = keeperPhase_ ? _keeper : _treasury();
        _callbackToken.armOutgoing(
            address(_payout),
            recipient,
            abi.encodeCall(_payout.transferPendingPayout, (address(_callbackToken), recipient)),
            false
        );
        vm.prank(address(_core));
        _payout.creditSeizure(address(_callbackToken), _keeper, 7, 11);
        _assertCallbackRejected();
        _assertBuckets(address(_callbackToken), _keeper, 0, 0, 0, 0);
        assertEq(_callbackToken.balanceOf(_keeper), 10, "Reward 3+7 delivered once");
        assertEq(_callbackToken.balanceOf(_treasury()), 15, "Seized 4+11 delivered once");
        assertEq(_unrelatedDigest(), other, "Other domains isolated");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-C02.
    function test_givenKeeperCallbackPropagates_whenCredited_thenOnlyItsBucketDeferred()
        public
        givenPendingBuckets
    {
        _seedUnrelatedClaims();
        _deferCallbackSeizure(3, 4);
        bytes32 other = _unrelatedDigest();
        _callbackToken.setTransferBlocked(_keeper, false);
        _callbackToken.setTransferBlocked(_treasury(), false);
        _callbackToken.mint(address(_payout), 43);
        bytes memory nested = abi.encodeCall(
            _payout.transferPendingPayout,
            (address(_callbackToken), _keeper)
        );
        _callbackToken.armOutgoing(address(_payout), _keeper, nested, true);
        vm.expectCall(address(_payout), nested, 2);
        vm.prank(address(_core));
        _payout.creditSeizure(address(_callbackToken), _keeper, 7, 11);
        _assertBuckets(address(_callbackToken), _keeper, 0, 0, 10, 10);
        assertEq(
            _callbackToken.balanceOf(address(_payout)),
            35,
            "Rejected reward and donation retained"
        );
        _callbackToken.disarm();
        assertEq(
            _payout.transferPendingPayout(address(_callbackToken), _keeper),
            10,
            "Retry pays retained allocation once"
        );
        assertEq(_unrelatedDigest(), other, "Other obligations isolated");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-C02.
    function test_givenTreasuryCallbackPropagates_whenCredited_thenOnlyItsBucketDeferred()
        public
        givenPendingBuckets
    {
        _seedUnrelatedClaims();
        _deferCallbackSeizure(3, 4);
        bytes32 other = _unrelatedDigest();
        _callbackToken.setTransferBlocked(_keeper, false);
        _callbackToken.setTransferBlocked(_treasury(), false);
        _callbackToken.mint(address(_payout), 43);
        bytes memory nested = abi.encodeCall(
            _payout.transferPendingPayout,
            (address(_callbackToken), _treasury())
        );
        _callbackToken.armOutgoing(address(_payout), _treasury(), nested, true);
        vm.expectCall(address(_payout), nested, 2);
        vm.prank(address(_core));
        _payout.creditSeizure(address(_callbackToken), _keeper, 7, 11);
        _assertBuckets(address(_callbackToken), _keeper, 0, 15, 0, 15);
        assertEq(
            _callbackToken.balanceOf(address(_payout)),
            40,
            "Rejected seizure and donation retained"
        );
        _callbackToken.disarm();
        assertEq(
            _payout.transferPendingPayout(address(_callbackToken), _treasury()),
            15,
            "Retry pays retained allocation once"
        );
        assertEq(_unrelatedDigest(), other, "Other obligations isolated");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-C01.
    function test_givenEachTransferPhase_whenCaughtCallback_thenBothPaidOnce() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenCaughtCallback_whenKeeperOrTreasuryPaid_thenBothAllocationsOnce(true);
        _restore(checkpoint);
        test_givenCaughtCallback_whenKeeperOrTreasuryPaid_thenBothAllocationsOnce(false);
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
