// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// Tests read state after calls to assert exact effects and rollback.
// Expected-revert calls and repeat-configuration probes discard their return values.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth, unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {NoReturnPayoutToken} from "./fixtures/NoReturnPayoutToken.sol";

contract BurnerLoansPayoutCreditFeeTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-CREDIT-FEE-I01.
    function test_givenInsufficientReceipt_whenFeeCredited_reverts() public {
        _asset.mint(address(_payout), 11);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InsufficientBalance.selector,
                address(_asset),
                11,
                12
            )
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_asset), 12);
        (, , uint256 total) = _payout.payoutReserves(address(_asset));
        assertEq(total, 0, "Rejected receipt adds no liability");
        assertEq(_asset.balanceOf(address(_payout)), 11, "Rejected receipt moves no funds");
    }

    // Scenarios: BLCU-CREDIT-FEE-N03.
    function test_givenPendingFees_whenAggregateOverflows_reverts() public {
        _deferFee(_token, 5);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_AmountOverflow.selector,
                5,
                type(uint256).max
            )
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), type(uint256).max);
        (uint256 fee, , uint256 total) = _payout.payoutReserves(address(_token));
        assertEq(fee, 5, "Overflow retains original fees");
        assertEq(total, 5, "Overflow retains aggregate reserve");
    }

    // Scenarios: BLCU-CREDIT-FEE-L01, BLCU-CREDIT-FEE-L03.
    function test_givenInactivePayout_whenCoreCredits_reverts(
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, false, enabled_);
        _expectCreditRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            ),
            address(_core),
            1
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-L02.
    function test_givenPausedPayout_whenCoreCredits_reverts() public givenPendingBuckets {
        _payout.disable("");
        _expectCreditRejected(
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            address(_core),
            1
        );
    }

    function test_whenCallerIsNotImmutableCore_reverts(address caller_) public givenPendingBuckets {
        vm.assume(caller_ != address(_core));
        _expectCreditRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_,
            1
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-L04, BLCU-CREDIT-FEE-N02, BLCU-CREDIT-FEE-P03.
    function test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery(
        uint256 amount_,
        uint256 oldFee_
    ) public {
        amount_ = bound(amount_, 1, type(uint256).max);
        oldFee_ = bound(oldFee_, 0, type(uint256).max - amount_);
        _bindDistributor();
        _deferFee(_token, oldFee_);
        _token.setTransferReverts(_treasury(), false);
        _payout.disable("");
        _payout.enable("");
        _token.mint(address(_payout), amount_);
        _expectPayoutTransferred(_treasury(), IBurnerLoansPayout.PayoutKind.Fee, oldFee_ + amount_);
        vm.prank(address(_core));
        _payout.creditFee(address(_token), amount_);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
        assertEq(
            _token.balanceOf(_treasury()),
            oldFee_ + amount_,
            "Treasury receives accumulated raw units once"
        );
        assertEq(_token.balanceOf(address(_distributor)), 0, "Unused distributor unchanged");
        assertEq(_token.balanceOf(address(_payout)), 0, "Fee custody emptied");
    }

    // Scenarios: BLCU-CREDIT-FEE-N02, BLCU-CREDIT-FEE-P04.
    function test_givenPendingFee_whenDistributorCreditSucceeds_thenCombinedDelivery(
        uint256 amount_,
        uint256 oldFee_
    ) public {
        amount_ = bound(amount_, 1, type(uint256).max);
        oldFee_ = bound(oldFee_, 0, type(uint256).max - amount_);
        _useDistributor();
        _deferFee(_token, oldFee_);
        _token.setTransferReverts(address(_distributor), false);
        _token.mint(address(_payout), amount_);
        _expectPayoutTransferred(
            address(_distributor),
            IBurnerLoansPayout.PayoutKind.Fee,
            oldFee_ + amount_
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), amount_);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
        assertEq(
            _token.balanceOf(address(_distributor)),
            oldFee_ + amount_,
            "Distributor receives accumulated raw units once"
        );
        assertEq(_token.balanceOf(_treasury()), 0, "Treasury unchanged");
    }

    // Scenarios: BLCU-CREDIT-FEE-N02, BLCU-CREDIT-FEE-P03, BLCU-CREDIT-FEE-P04.
    function test_givenFeeBoundarySeeds_whenCredited_thenCombinedDelivery() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery(1, 0);
        _restore(checkpoint);
        test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery(
            1,
            type(uint256).max - 1
        );
        _restore(checkpoint);
        test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery(type(uint256).max, 0);
        _restore(checkpoint);
        test_givenPendingFee_whenDistributorCreditSucceeds_thenCombinedDelivery(1, 0);
        _restore(checkpoint);
        test_givenPendingFee_whenDistributorCreditSucceeds_thenCombinedDelivery(
            1,
            type(uint256).max - 1
        );
        _restore(checkpoint);
        test_givenPendingFee_whenDistributorCreditSucceeds_thenCombinedDelivery(
            type(uint256).max,
            0
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-N01.
    function test_givenPendingOrEmptyFee_whenZeroCredited_thenNoRetry(uint256 oldFee_) public {
        _deferFee(_token, oldFee_);
        _token.setTransferReverts(_treasury(), false);
        bytes32 state = _ledgerDigest();
        uint256 calls = _token.transferCallCount();
        vm.recordLogs();
        vm.prank(address(_core));
        _payout.creditFee(address(_token), 0);
        assertEq(vm.getRecordedLogs().length, 0, "Zero fee emits no event");
        assertEq(_token.transferCallCount(), calls, "Zero fee does not retry old obligation");
        assertEq(_ledgerDigest(), state, "Zero credit preserves every bucket");
    }

    // Scenarios: BLCU-CREDIT-FEE-N01.
    function test_givenPendingAndEmptyFeeSeeds_whenZeroCredited_thenNoRetry() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPendingOrEmptyFee_whenZeroCredited_thenNoRetry(0);
        _restore(checkpoint);
        test_givenPendingOrEmptyFee_whenZeroCredited_thenNoRetry(type(uint256).max);
    }

    // Scenarios: BLCU-CREDIT-FEE-I01.
    function test_givenReceiptOneUnitShort_whenCredited_reverts(
        uint256 amount_,
        uint256 oldFee_
    ) public {
        amount_ = bound(amount_, 1, type(uint256).max);
        oldFee_ = bound(oldFee_, 0, type(uint256).max - amount_);
        _deferFee(_token, oldFee_);
        _token.mint(address(_payout), amount_ - 1);
        _expectCreditRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InsufficientBalance.selector,
                address(_token),
                oldFee_ + amount_ - 1,
                oldFee_ + amount_
            ),
            address(_core),
            amount_
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-D01.
    function test_givenBlockedRecipient_whenCredited_thenCompleteFeeDeferred(
        uint256 amount_,
        uint256 oldFee_
    ) public {
        amount_ = bound(amount_, 1, type(uint256).max);
        oldFee_ = bound(oldFee_, 0, type(uint256).max - amount_);
        _deferFee(_token, oldFee_);
        _token.mint(address(_payout), amount_);
        _expectPayoutDeferred(_treasury(), IBurnerLoansPayout.PayoutKind.Fee, oldFee_ + amount_);
        vm.prank(address(_core));
        _payout.creditFee(address(_token), amount_);
        _assertBuckets(address(_token), _keeper, oldFee_ + amount_, 0, 0, oldFee_ + amount_);
        assertEq(
            _token.balanceOf(address(_payout)),
            oldFee_ + amount_,
            "Failed optional payout stays backed"
        );
        assertEq(_token.balanceOf(_treasury()), 0, "No payment");
    }

    // Scenarios: BLCU-CREDIT-FEE-D02.
    function test_givenTransferReturnsFalse_whenCredited_thenFeeDeferred() public {
        vm.mockCall(
            address(_token),
            abi.encodeCall(_token.transfer, (_treasury(), uint256(10))),
            abi.encode(false)
        );
        _token.mint(address(_payout), 10);
        _expectPayoutDeferred(_treasury(), IBurnerLoansPayout.PayoutKind.Fee, 10);
        vm.prank(address(_core));
        _payout.creditFee(address(_token), 10);
        _assertBuckets(address(_token), _keeper, 10, 0, 0, 10);
        assertEq(_token.balanceOf(address(_payout)), 10, "False return leaves custody backing");
    }

    // Scenarios: BLCU-CREDIT-FEE-P01.
    function test_givenTokenReturnsNoData_whenCredited_thenDelivered() public {
        _token.mint(address(_payout), 10);
        vm.mockFunction(
            address(_token),
            address(new NoReturnPayoutToken()),
            abi.encodeWithSignature("transfer(address,uint256)")
        );
        _expectPayoutTransferred(_treasury(), IBurnerLoansPayout.PayoutKind.Fee, 10);
        vm.prank(address(_core));
        _payout.creditFee(address(_token), 10);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
        assertEq(_token.balanceOf(_treasury()), 10, "No-return token actually delivered");
    }

    // Scenarios: BLCU-CREDIT-FEE-P07.
    function test_givenCoreSelectionGetterRejects_whenCredited_thenNoSelectionRead() public {
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("payout()"), hex"deadbeef");
        _creditFee(_token, 10);
        assertEq(
            _token.balanceOf(_treasury()),
            10,
            "Immutable Core credit does not inspect reverse selection"
        );
    }

    function _expectCreditRejected(
        bytes memory reason_,
        address caller_,
        uint256 amount_
    ) internal {
        bytes32 state = _ledgerDigest();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.creditFee(address(_token), amount_);
        assertEq(
            _ledgerDigest(),
            state,
            "Rejected credit restores liabilities, indexes and custody"
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-N03.
    function test_givenPendingFees_whenNewAmountOverflows_thenExactError(
        uint256 pending_,
        uint256 amount_
    ) public {
        pending_ = bound(pending_, 1, type(uint256).max);
        amount_ = bound(amount_, type(uint256).max - pending_ + 1, type(uint256).max);
        _deferFee(_token, pending_);
        _expectCreditRejected(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_AmountOverflow.selector,
                pending_,
                amount_
            ),
            address(_core),
            amount_
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-L05.
    function test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _deactivatePayoutWithBrokenRoles(caller_, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.creditFee(address(_token), 1);
        assertEq(_ledgerDigest(), state, "Inactivity rejects before authority or mutation");
    }

    // Scenarios: BLCU-CREDIT-FEE-L06.
    function test_givenActivePausedPayout_whenNonCoreCredits_thenEnablementWins()
        public
        givenPendingBuckets
    {
        _payout.disable("");
        bytes32 state = _ledgerDigest();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_recipient);
        _payout.creditFee(address(_token), 1);
        assertEq(_ledgerDigest(), state, "Pause rejects before Core caller authentication");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth, unused-return)
