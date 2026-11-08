// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// Tests read state after calls to assert exact effects and rollback.
// Expected-revert calls and repeat-configuration probes discard their return values.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth, unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {NoReturnPayoutToken} from "./fixtures/NoReturnPayoutToken.sol";
import {Actions} from "src/Kernel.sol";

contract BurnerLoansPayoutCreditFeeTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-CREDIT-FEE-P12.
    function test_givenAllBucketsPending_whenReservesRead() public {
        _seedBuckets(11, 7, 5, _keeper);
        _token.setTransferReverts(_secondKeeper, true);
        _creditReferral(_token, 0, _keeper, 13);
        _creditReferral(_token, 0, _secondKeeper, 17);
        (bool success, bytes memory result) = address(_payout).staticcall(
            abi.encodeCall(_payout.pendingAmounts, (address(_token)))
        );
        assertTrue(success, "Reserve getter succeeds");
        assertEq(result.length, 5 * 32, "Reserve API exposes every bucket and the total");
        (uint256 protocol, uint256 referral, uint256 seized, uint256 keeper, uint256 total) = abi
            .decode(result, (uint256, uint256, uint256, uint256, uint256));
        assertEq(protocol, 11, "Protocol fees exclude referral allocations");
        assertEq(referral, 30, "Referral reserve sums both original recipients: 13 + 17");
        assertEq(seized, 7, "Seized collateral remains separate");
        assertEq(
            keeper,
            5,
            "Keeper rewards are reported separately from protocol and referral fees"
        );
        assertEq(
            total,
            protocol + referral + seized + keeper,
            "Every pending bucket sums to the total"
        );
        assertEq(total, 53, "Total includes protocol11 + referral30 + seized7 + keeper5");
    }

    // Scenarios: BLCU-CREDIT-FEE-L07.
    function test_givenPendingReferral_whenReadUnderLifecycleStates(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _token.setTransferReverts(_keeper, true);
        _creditReferral(_token, 0, _keeper, 25);
        _seedBuckets(11, 13, 7, _keeper);
        _setState(_payout, active_, enabled_);
        _assertLifecyclePendingClaims(caller_);
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        if (!enabled_) _payout.enable("");
        _assertLifecyclePendingClaims(caller_);
    }

    // Scenarios: BLCU-CREDIT-FEE-L07.
    function test_givenPendingClaims_whenLifecycleBoundaryStates() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPendingReferral_whenReadUnderLifecycleStates(address(0), false, false);
        _restore(checkpoint);
        test_givenPendingReferral_whenReadUnderLifecycleStates(address(0), false, true);
        _restore(checkpoint);
        test_givenPendingReferral_whenReadUnderLifecycleStates(
            address(type(uint160).max),
            true,
            false
        );
        _restore(checkpoint);
        test_givenPendingReferral_whenReadUnderLifecycleStates(
            address(type(uint160).max),
            true,
            true
        );
    }

    function _assertLifecyclePendingClaims(address caller_) private {
        address treasuryRecipient = _treasury();
        vm.startPrank(caller_);
        _assertBuckets(address(_token), _keeper, 11, 13, 7, 56);
        _assertReferral(address(_token), _keeper, 25);
        assertEq(
            _payout.pendingRecipientAmount(address(_token), _keeper),
            32,
            "Keeper7 plus referral25 remains readable"
        );
        assertEq(
            _payout.pendingRecipientAmount(address(_token), treasuryRecipient),
            24,
            "Protocol11 plus seized13 remains readable"
        );
        assertEq(
            _payout.pendingKeeperReward(address(_token), _keeper),
            7,
            "Dedicated keeper getter is independent of caller and lifecycle"
        );
        address[] memory recipients = _payout.getPendingPayoutRecipients(address(_token));
        assertEq(
            recipients.length,
            2,
            "Two distinct recipients remain enumerable in every lifecycle state"
        );
        assertEq(recipients[0], _keeper, "Original keeper/referrer stays fixed");
        assertEq(
            recipients[1],
            treasuryRecipient,
            "Protocol route stays fixed during lifecycle changes"
        );
        assertEq(
            _token.balanceOf(address(_payout)),
            56,
            "Lifecycle changes and reads retain exact custody backing"
        );
        vm.stopPrank();
    }

    // Scenarios: BLCU-CREDIT-FEE-P15.
    function test_whenPendingGettersReadForEmptyToken(
        address caller_,
        address token_,
        address recipient_
    ) public {
        vm.expectCall(
            token_,
            abi.encodeWithSelector(_token.balanceOf.selector, address(_payout)),
            uint64(0)
        );
        vm.startPrank(caller_);
        (
            uint256 protocol,
            uint256 referral,
            uint256 seized,
            uint256 keeper,
            uint256 total
        ) = _payout.pendingAmounts(token_);
        assertEq(protocol, 0, "Empty token has no protocol fees");
        assertEq(referral, 0, "Empty token has no referral fees");
        assertEq(seized, 0, "Empty token has no seized collateral");
        assertEq(keeper, 0, "Empty token has no keeper rewards");
        assertEq(total, 0, "Empty token has no aggregate obligation");
        assertEq(
            _payout.pendingRecipientAmount(token_, recipient_),
            0,
            "Unknown recipient has no combined entitlement"
        );
        assertEq(
            _payout.pendingKeeperReward(token_, recipient_),
            0,
            "Unknown keeper has no reward"
        );
        assertEq(
            _payout.pendingReferralFee(token_, recipient_),
            0,
            "Unknown referrer has no referral fee"
        );
        assertEq(
            _payout.getPendingPayoutRecipients(token_).length,
            0,
            "Empty token has no recipient index entries"
        );
        vm.stopPrank();
    }

    // Scenarios: BLCU-CREDIT-FEE-P15.
    function test_whenEmptyGetterBoundarySeeds() public {
        test_whenPendingGettersReadForEmptyToken(address(0), address(0), address(0));
        address maximum = address(type(uint160).max);
        test_whenPendingGettersReadForEmptyToken(maximum, maximum, maximum);
    }

    // Scenarios: BLCU-CREDIT-FEE-P13.
    function test_givenOverlappingRecipientSets_whenRecipientsRead() public {
        _seedBuckets(11, 7, 5, _keeper);
        _deferSeizure(_token, _secondKeeper, 3, 0);
        _token.setTransferReverts(_thirdKeeper, true);
        _creditReferral(_token, 0, _keeper, 13);
        _creditReferral(_token, 0, _thirdKeeper, 17);
        address[] memory recipients = _payout.getPendingPayoutRecipients(address(_token));
        assertEq(recipients.length, 4, "Keeper/referrer and fee/Treasury overlaps appear once");
        assertEq(recipients[0], _keeper, "First keeper retained");
        assertEq(recipients[1], _secondKeeper, "Second keeper retained");
        assertEq(recipients[2], _thirdKeeper, "Only the additional referrer is appended");
        assertEq(recipients[3], _treasury(), "Shared protocol destination appended once");
        assertEq(
            _payout.pendingRecipientAmount(address(_token), _keeper),
            18,
            "Keeper5 plus referral13"
        );
        assertEq(
            _payout.pendingRecipientAmount(address(_token), _treasury()),
            18,
            "Protocol11 plus seized7"
        );
        assertEq(
            _payout.getPendingPayoutRecipients(address(_otherToken)).length,
            0,
            "Empty token has no recipients"
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-I03.
    function test_whenZeroReferrerHasPositiveReferralFee_reverts(
        uint256 protocol_,
        uint256 referralFee_
    ) public {
        referralFee_ = bound(referralFee_, 1, type(uint256).max);
        protocol_ = bound(protocol_, 0, type(uint256).max - referralFee_);
        bytes32 beforeState = _ledgerDigest();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector);
        vm.prank(address(_core));
        _payout.creditFee(address(_token), protocol_, address(0), referralFee_);
        assertEq(_ledgerDigest(), beforeState, "Invalid attribution changes no custody or reserve");
        _assertReferral(address(_token), address(0), 0);
    }

    // Scenarios: BLCU-CREDIT-FEE-N08.
    function test_whenComponentsOverflow_reverts(uint256 protocol_, uint256 referralFee_) public {
        protocol_ = bound(protocol_, 1, type(uint256).max);
        referralFee_ = bound(referralFee_, type(uint256).max - protocol_ + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_AmountOverflow.selector,
                protocol_,
                referralFee_
            )
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), protocol_, _keeper, referralFee_);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
        _assertReferral(address(_token), _keeper, 0);
    }

    // Scenarios: BLCU-CREDIT-FEE-N04.
    function test_whenReferralUsesFullUint256() public {
        _token.setTransferReverts(_keeper, true);
        _creditReferral(_token, 0, _keeper, type(uint256).max);
        _assertReferral(address(_token), _keeper, type(uint256).max);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, type(uint256).max);
        assertEq(
            _token.balanceOf(address(_payout)),
            type(uint256).max,
            "Maximum referral fee remains fully backed"
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-N05, BLCU-CREDIT-FEE-P11.
    function test_whenNonzeroReferrerHasZeroReferralFee(
        uint256 protocol_,
        bool zeroReferrer_
    ) public {
        protocol_ = bound(protocol_, 1, type(uint256).max);
        address referrer = zeroReferrer_ ? address(0) : _keeper;
        vm.recordLogs();
        _creditReferral(_token, protocol_, referrer, 0);
        assertEq(
            _token.balanceOf(_treasury()),
            protocol_,
            "Protocol receives its complete allocation"
        );
        _assertReferral(address(_token), referrer, 0);
        assertEq(
            _payout.getPendingReferralRecipients(address(_token)).length,
            0,
            "Zero referral fee adds no recipient"
        );
        assertEq(vm.getRecordedLogs().length, 3, "Mint, transfer and protocol payout events only");
    }

    // Scenarios: BLCU-CREDIT-FEE-P08.
    function test_whenProtocolAndReferralBothDelivered() public {
        _token.mint(address(_payout), 101);
        vm.recordLogs();
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutTransferred(
            address(_token),
            _treasury(),
            IBurnerLoansPayout.PayoutKind.Fee,
            76
        );
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutTransferred(
            address(_token),
            _keeper,
            IBurnerLoansPayout.PayoutKind.Referral,
            25
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), 76, _keeper, 25);
        // 101 raw collateral units = 76 protocol + 25 referral; no rescaling occurs here.
        assertEq(_token.balanceOf(_treasury()), 76, "Protocol receives the supplied remainder");
        assertEq(_token.balanceOf(_keeper), 25, "Original referrer receives the supplied reward");
        assertEq(_token.balanceOf(address(_payout)), 0, "Complete receipt distributed");
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
        _assertReferral(address(_token), _keeper, 0);
    }

    // Scenarios: BLCU-CREDIT-FEE-T01.
    function test_givenReferralDeliveryBlocked_whenFeeCredited() public {
        _token.setTransferReverts(_keeper, true);
        _token.mint(address(_payout), 101);
        vm.recordLogs();
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutTransferred(
            address(_token),
            _treasury(),
            IBurnerLoansPayout.PayoutKind.Fee,
            76
        );
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutDeferred(
            address(_token),
            _keeper,
            IBurnerLoansPayout.PayoutKind.Referral,
            25
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), 76, _keeper, 25);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 25);
        _assertReferral(address(_token), _keeper, 25);
        assertEq(_token.balanceOf(_keeper), 0, "Blocked referral receives nothing");
        assertEq(
            _token.balanceOf(_treasury()),
            76,
            "Protocol still receives its supplied allocation"
        );
        assertEq(_token.balanceOf(address(_payout)), 25, "Deferred referral stays backed");
    }

    // Scenarios: BLCU-CREDIT-FEE-T02.
    function test_givenProtocolDeliveryBlocked_whenFeeCredited() public {
        _token.setTransferReverts(_treasury(), true);
        _token.mint(address(_payout), 101);
        vm.recordLogs();
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutDeferred(
            address(_token),
            _treasury(),
            IBurnerLoansPayout.PayoutKind.Fee,
            76
        );
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutTransferred(
            address(_token),
            _keeper,
            IBurnerLoansPayout.PayoutKind.Referral,
            25
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), 76, _keeper, 25);
        _assertBuckets(address(_token), _keeper, 76, 0, 0, 76);
        _assertReferral(address(_token), _keeper, 0);
        assertEq(_token.balanceOf(_keeper), 25, "Referral still receives its supplied allocation");
        assertEq(_token.balanceOf(_treasury()), 0, "Blocked protocol receives nothing");
        assertEq(
            _token.balanceOf(address(_payout)),
            76,
            "Deferred protocol allocation stays backed"
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-T03.
    function test_givenBothDeliveriesBlocked_whenFeeCredited() public {
        _token.setTransferReverts(_keeper, true);
        _token.setTransferReverts(_treasury(), true);
        _token.mint(address(_payout), 101);
        vm.recordLogs();
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutDeferred(
            address(_token),
            _treasury(),
            IBurnerLoansPayout.PayoutKind.Fee,
            76
        );
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutDeferred(
            address(_token),
            _keeper,
            IBurnerLoansPayout.PayoutKind.Referral,
            25
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), 76, _keeper, 25);
        _assertBuckets(address(_token), _keeper, 76, 0, 0, 101);
        _assertReferral(address(_token), _keeper, 25);
        assertEq(_token.balanceOf(_keeper), 0, "Blocked referral receives nothing");
        assertEq(_token.balanceOf(_treasury()), 0, "Blocked protocol receives nothing");
        assertEq(
            _token.balanceOf(address(_payout)),
            101,
            "Both fixed allocations remain fully backed"
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-T04.
    function test_whenReferrerEqualsPayout_reverts(uint256 protocol_, uint256 referral_) public {
        referral_ = bound(referral_, 1, type(uint256).max);
        protocol_ = bound(protocol_, 0, type(uint256).max - referral_);
        bytes32 beforeState = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
                address(_payout)
            )
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), protocol_, address(_payout), referral_);
        assertEq(
            _ledgerDigest(),
            beforeState,
            "Self-referral rejects before custody reads, credit or delivery"
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-T04.
    function test_whenSelfReferrerBoundarySeeds_reverts() public {
        test_whenReferrerEqualsPayout_reverts(0, 1);
        test_whenReferrerEqualsPayout_reverts(0, type(uint256).max);
        test_whenReferrerEqualsPayout_reverts(type(uint256).max - 1, 1);
    }

    // Scenarios: BLCU-CREDIT-FEE-P14.
    function test_whenReferrerEqualsPayout_whenReferralFeeZero() public {
        _creditReferral(_token, 76, address(_payout), 0);
        _assertReferral(address(_token), address(_payout), 0);
        assertEq(
            _token.balanceOf(_treasury()),
            76,
            "Unused referrer does not block protocol allocation"
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-T06.
    function test_givenProtocolRouteEqualsPayout_whenFeeCredited_reverts(uint256 protocol_) public {
        protocol_ = bound(protocol_, 1, type(uint256).max);
        _token.mint(address(_payout), protocol_);
        _mockTreasuryRecipient(address(_payout));
        bytes32 beforeState = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
                address(_payout)
            )
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), protocol_, address(0), 0);
        assertEq(
            _ledgerDigest(),
            beforeState,
            "Invalid protocol route creates no liability or transfer"
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-T06.
    function test_givenProtocolRouteEqualsPayout_whenFeeBoundarySeeds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenProtocolRouteEqualsPayout_whenFeeCredited_reverts(1);
        _restore(checkpoint);
        test_givenProtocolRouteEqualsPayout_whenFeeCredited_reverts(type(uint256).max);
    }

    // Scenarios: BLCU-CREDIT-FEE-T05.
    function test_givenOldReferralReserve_whenNewReceiptIsOneShort_reverts(
        uint256 old_,
        uint256 receipt_,
        uint256 protocol_
    ) public {
        old_ = bound(old_, 1, type(uint256).max - 1);
        receipt_ = bound(receipt_, 1, type(uint256).max - old_);
        protocol_ = bound(protocol_, 0, receipt_);
        uint256 referral = receipt_ - protocol_;
        _token.setTransferReverts(_keeper, true);
        _creditReferral(_token, 0, _keeper, old_);
        _token.mint(address(_payout), receipt_ - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InsufficientBalance.selector,
                address(_token),
                old_ + receipt_ - 1,
                old_ + receipt_
            )
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), protocol_, _secondKeeper, referral);
        _assertReferral(address(_token), _keeper, old_);
        _assertReferral(address(_token), _secondKeeper, 0);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, old_);
        assertEq(
            _token.balanceOf(address(_payout)),
            old_ + receipt_ - 1,
            "Rejected credit never consumes old backing"
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-N07.
    function test_givenReferralReserve_whenCombinedReserveOverflows_reverts(
        uint256 old_,
        uint256 receipt_,
        uint256 protocol_
    ) public {
        old_ = bound(old_, 1, type(uint256).max);
        receipt_ = bound(receipt_, type(uint256).max - old_ + 1, type(uint256).max);
        protocol_ = bound(protocol_, 0, receipt_);
        _token.setTransferReverts(_keeper, true);
        _creditReferral(_token, 0, _keeper, old_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_AmountOverflow.selector,
                old_,
                receipt_
            )
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), protocol_, _secondKeeper, receipt_ - protocol_);
        _assertReferral(address(_token), _keeper, old_);
        _assertReferral(address(_token), _secondKeeper, 0);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, old_);
    }

    // Scenarios: BLCU-CREDIT-FEE-T05.
    function test_givenReferralReserve_whenShortReceiptBoundarySeeds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenOldReferralReserve_whenNewReceiptIsOneShort_reverts(25, 101, 76);
        _restore(checkpoint);
        test_givenOldReferralReserve_whenNewReceiptIsOneShort_reverts(1, type(uint256).max - 1, 0);
        _restore(checkpoint);
        test_givenOldReferralReserve_whenNewReceiptIsOneShort_reverts(type(uint256).max - 1, 1, 1);
    }

    // Scenarios: BLCU-CREDIT-FEE-N07.
    function test_givenReferralReserve_whenAggregateOverflowBoundarySeeds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenReferralReserve_whenCombinedReserveOverflows_reverts(1, type(uint256).max, 0);
        _restore(checkpoint);
        test_givenReferralReserve_whenCombinedReserveOverflows_reverts(type(uint256).max, 1, 0);
    }

    // Scenarios: BLCU-CREDIT-FEE-P09.
    function test_givenOverlappingOldBuckets_whenNewReferralFeeAccrues() public {
        address recipient = _treasury();
        _deferFee(_token, 30);
        _deferSeizure(_token, recipient, 10, 20);
        _creditReferral(_token, 0, recipient, 40);
        _token.setTransferReverts(recipient, false);
        _token.mint(address(_payout), 101);
        vm.recordLogs();
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutTransferred(
            address(_token),
            recipient,
            IBurnerLoansPayout.PayoutKind.Fee,
            106
        );
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PayoutTransferred(
            address(_token),
            recipient,
            IBurnerLoansPayout.PayoutKind.Referral,
            65
        );
        vm.prank(address(_core));
        _payout.creditFee(address(_token), 76, recipient, 25);
        assertEq(_token.balanceOf(recipient), 171, "Protocol106 plus referral65 paid separately");
        _assertBuckets(address(_token), recipient, 0, 20, 10, 30);
        _assertReferral(address(_token), recipient, 0);
    }

    // Scenarios: BLCU-CREDIT-FEE-P10.
    function test_givenDifferentRecipientsAndAssets_whenReferralFeesAccrue() public {
        _token.setTransferReverts(_keeper, true);
        _token.setTransferReverts(_secondKeeper, true);
        _otherToken.setTransferReverts(_keeper, true);
        vm.recordLogs();
        _creditReferral(_token, 0, _keeper, 11);
        vm.recordLogs();
        _creditReferral(_token, 0, _keeper, 13);
        vm.recordLogs();
        _creditReferral(_token, 0, _secondKeeper, 17);
        vm.recordLogs();
        _creditReferral(_otherToken, 0, _keeper, 19);
        _assertReferral(address(_token), _keeper, 24);
        _assertReferral(address(_token), _secondKeeper, 17);
        _assertReferral(address(_otherToken), _keeper, 19);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 41);
        assertEq(
            _payout.getPendingReferralRecipients(address(_token)).length,
            2,
            "Repeated owners do not duplicate recipients"
        );
        assertEq(
            _payout.getPendingPayoutRecipients(address(_token)).length,
            2,
            "Combined recipient getter includes referrals"
        );
    }

    // Scenarios: BLCU-CREDIT-FEE-N01.
    function test_givenPendingReferral_whenZeroAllocationCredited() public {
        _token.setTransferReverts(_keeper, true);
        _creditReferral(_token, 0, _keeper, 25);
        _token.setTransferReverts(_keeper, false);
        uint256 transfers = _token.transferCallCount();
        vm.recordLogs();
        vm.prank(address(_core));
        _payout.creditFee(address(_token), 0, _keeper, 0);
        assertEq(vm.getRecordedLogs().length, 0, "Zero total adds no accrual and makes no retry");
        assertEq(
            _token.transferCallCount(),
            transfers,
            "Zero referral does not sweep an existing entitlement"
        );
        _assertReferral(address(_token), _keeper, 25);
    }

    // Scenarios: BLCU-CREDIT-FEE-I03.
    function test_whenZeroReferrerBoundarySeeds_reverts() public {
        test_whenZeroReferrerHasPositiveReferralFee_reverts(0, 1);
        test_whenZeroReferrerHasPositiveReferralFee_reverts(0, type(uint256).max);
        test_whenZeroReferrerHasPositiveReferralFee_reverts(type(uint256).max - 1, 1);
    }

    // Scenarios: BLCU-CREDIT-FEE-N08.
    function test_whenComponentOverflowBoundarySeeds_reverts() public {
        test_whenComponentsOverflow_reverts(1, type(uint256).max);
        test_whenComponentsOverflow_reverts(type(uint256).max, 1);
        test_whenComponentsOverflow_reverts(type(uint256).max, type(uint256).max);
    }

    // Scenarios: BLCU-CREDIT-FEE-N05.
    function test_whenNonzeroReferrerHasMaximumProtocolFee() public {
        test_whenNonzeroReferrerHasZeroReferralFee(type(uint256).max, false);
    }

    // Scenarios: BLCU-CREDIT-FEE-N04, BLCU-CREDIT-FEE-N05, BLCU-CREDIT-FEE-T03.
    function test_whenFullWidthAllocationsRemainPending(
        uint256 protocol_,
        uint256 referral_,
        address recipient_
    ) public {
        vm.assume(recipient_ != address(0) && recipient_ != address(_payout));
        referral_ = bound(referral_, 0, type(uint256).max - protocol_);
        _token.setTransferReverts(_treasury(), true);
        _token.setTransferReverts(recipient_, true);
        _creditReferral(_token, protocol_, recipient_, referral_);
        _assertReferral(address(_token), recipient_, referral_);
        _assertBuckets(address(_token), _keeper, protocol_, 0, 0, protocol_ + referral_);
        assertEq(
            _token.balanceOf(address(_payout)),
            protocol_ + referral_,
            "Arbitrary complete receipt backs both independent allocations"
        );
    }

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
        _payout.creditFee(address(_asset), 12, address(0), 0);
        (, , , , uint256 total) = _payout.pendingAmounts(address(_asset));
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
        _payout.creditFee(address(_token), type(uint256).max, address(0), 0);
        (uint256 fee, , , , uint256 total) = _payout.pendingAmounts(address(_token));
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
        _payout.creditFee(address(_token), amount_, address(0), 0);
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
        _payout.creditFee(address(_token), amount_, address(0), 0);
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
        _payout.creditFee(address(_token), 0, address(0), 0);
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
        _payout.creditFee(address(_token), amount_, address(0), 0);
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
        _payout.creditFee(address(_token), 10, address(0), 0);
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
        _payout.creditFee(address(_token), 10, address(0), 0);
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
        _payout.creditFee(address(_token), amount_, address(0), 0);
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
        _payout.creditFee(address(_token), 1, address(0), 0);
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
        _payout.creditFee(address(_token), 1, address(0), 0);
        assertEq(_ledgerDigest(), state, "Pause rejects before Core caller authentication");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth, unused-return)
