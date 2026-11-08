// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// Expected-revert calls and repeat-configuration probes discard their return values.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";

contract BurnerLoansPayoutCreditSeizureTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-CREDIT-SEIZURE-D04.
    function test_whenKeeperIsZero_whenRewardPositive_reverts(
        uint256 reward_,
        uint256 seized_
    ) public {
        reward_ = bound(reward_, 1, type(uint256).max);
        seized_ = bound(seized_, 0, type(uint256).max - reward_);
        bytes32 beforeState = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
                address(0)
            )
        );
        vm.prank(address(_core));
        _payout.creditSeizure(address(_token), address(0), reward_, seized_);
        assertEq(_ledgerDigest(), beforeState, "Zero keeper rejects before credit or transfer");
        assertEq(
            _payout.pendingKeeperReward(address(_token), address(0)),
            0,
            "Zero keeper has no claim"
        );
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-D04.
    function test_whenZeroKeeperRewardBoundarySeeds_reverts() public {
        test_whenKeeperIsZero_whenRewardPositive_reverts(1, 0);
        test_whenKeeperIsZero_whenRewardPositive_reverts(type(uint256).max, 0);
        test_whenKeeperIsZero_whenRewardPositive_reverts(1, type(uint256).max - 1);
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-P05.
    function test_whenKeeperIsZero_whenRewardZero() public {
        _creditSeizure(_token, address(0), 0, 7);
        _assertBuckets(address(_token), address(0), 0, 0, 0, 0);
        assertEq(_token.balanceOf(_treasury()), 7, "Unused zero keeper permits Treasury payout");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-P04.
    function test_givenOverlappingEntitlements_whenKeeperRewardRead(address caller_) public {
        address recipient = _treasury();
        _seedBuckets(7, 17, 11, recipient);
        _creditReferral(_token, 0, recipient, 13);
        _deferSeizure(_token, _secondKeeper, 3, 0);
        _deferSeizure(_otherToken, _secondKeeper, 5, 0);
        vm.startPrank(caller_);
        assertEq(
            _payout.pendingKeeperReward(address(_token), recipient),
            11,
            "Keeper bucket excludes referral and protocol allocations"
        );
        assertEq(
            _payout.pendingRecipientAmount(address(_token), recipient),
            48,
            "Recipient total includes keeper11 plus referral13 plus protocol7 plus seized17"
        );
        assertEq(
            _payout.pendingKeeperReward(address(_token), _secondKeeper),
            3,
            "Another keeper has a separate claim"
        );
        assertEq(
            _payout.pendingKeeperReward(address(_otherToken), _secondKeeper),
            5,
            "Another token has a separate claim"
        );
        assertEq(
            _payout.pendingKeeperReward(address(_token), address(0)),
            0,
            "Unknown zero keeper has no claim"
        );
        assertEq(
            _payout.pendingKeeperReward(address(0), recipient),
            0,
            "Unknown zero token has no claim"
        );
        vm.stopPrank();
        _assertBuckets(address(_token), recipient, 7, 17, 11, 51);
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-D02.
    function test_whenKeeperEqualsPayout_reverts(uint256 reward_, uint256 seized_) public {
        reward_ = bound(reward_, 1, type(uint256).max);
        seized_ = bound(seized_, 0, type(uint256).max - reward_);
        bytes32 beforeState = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
                address(_payout)
            )
        );
        vm.prank(address(_core));
        _payout.creditSeizure(address(_token), address(_payout), reward_, seized_);
        assertEq(
            _ledgerDigest(),
            beforeState,
            "Self-keeper rejects before accounting or outgoing transfers"
        );
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-D02.
    function test_whenSelfKeeperBoundarySeeds_reverts() public {
        test_whenKeeperEqualsPayout_reverts(1, 0);
        test_whenKeeperEqualsPayout_reverts(type(uint256).max, 0);
        test_whenKeeperEqualsPayout_reverts(1, type(uint256).max - 1);
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-P03.
    function test_whenKeeperEqualsPayout_whenRewardZero() public {
        _creditSeizure(_token, address(_payout), 0, 7);
        _assertBuckets(address(_token), address(_payout), 0, 0, 0, 0);
        assertEq(
            _token.balanceOf(_treasury()),
            7,
            "Unused keeper does not block Treasury allocation"
        );
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-D03.
    function test_givenTreasuryEqualsPayout_whenSeizureCredited_reverts() public {
        _token.mint(address(_payout), 12);
        _mockTreasuryRecipient(address(_payout));
        bytes32 beforeState = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
                address(_payout)
            )
        );
        vm.prank(address(_core));
        _payout.creditSeizure(address(_token), _keeper, 5, 7);
        assertEq(
            _ledgerDigest(),
            beforeState,
            "Invalid Treasury route rejects before keeper credit or transfer"
        );
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-N02.
    function test_whenRewardAndRemainderOverflow_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_AmountOverflow.selector,
                type(uint256).max,
                1
            )
        );
        vm.prank(address(_core));
        _payout.creditSeizure(address(_asset), _recipient, type(uint256).max, 1);
        (, , , , uint256 total) = _payout.pendingAmounts(address(_asset));
        assertEq(total, 0, "Allocation overflow adds no reserve");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-N01.
    function test_givenPendingFees_whenSeizureReceiptIsShort_reverts() public {
        _deferFee(_token, 5);
        _token.mint(address(_payout), 6);
        // Existing reserve 5 + reward 4 + remainder 3 = 12, against actual balance 11.
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InsufficientBalance.selector,
                address(_token),
                11,
                12
            )
        );
        vm.prank(address(_core));
        _payout.creditSeizure(address(_token), _recipient, 4, 3);
        (uint256 fee, , uint256 seized, , uint256 total) = _payout.pendingAmounts(address(_token));
        assertEq(fee, 5, "Original fee preserved");
        assertEq(seized, 0, "No seized credit");
        assertEq(total, 5, "Original aggregate preserved");
        assertEq(_token.balanceOf(address(_payout)), 11, "Neither payout attempted");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-N03.
    function test_givenPendingReserve_whenCombinedCreditOverflows_reverts() public {
        _deferFee(_token, 5);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_AmountOverflow.selector,
                5,
                type(uint256).max - 4
            )
        );
        vm.prank(address(_core));
        _payout.creditSeizure(address(_token), _recipient, type(uint256).max - 5, 1);
        (, , , , uint256 total) = _payout.pendingAmounts(address(_token));
        assertEq(total, 5, "Rejected allocation preserves existing reserve");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-P02.
    function test_whenCallerIsNotCore_reverts(address caller_) public givenPendingBuckets {
        vm.assume(caller_ != address(_core));
        _expectSeizureRejected(
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector),
            caller_
        );
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-L01, BLCU-CREDIT-SEIZURE-L03.
    function test_givenInactivePayout_whenCredited_reverts(
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, false, enabled_);
        _expectSeizureRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            ),
            address(_core)
        );
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-L02, BLCU-CREDIT-SEIZURE-P01.
    function test_givenReplacedAndPausedPayout_whenCredited_revertsButClaimsRemain()
        public
        givenPendingBuckets
    {
        _core.setPayout(address(_otherPayout));
        _payout.disable("");
        _expectSeizureRejected(
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            address(_core)
        );
        _token.setTransferReverts(_keeper, false);
        vm.prank(_recipient);
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            30,
            "Retired keeper claim remains payable"
        );
        _assertBuckets(address(_token), _keeper, 10, 20, 0, 30);
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-L04, BLCU-CREDIT-SEIZURE-I01.
    function test_givenOldBuckets_whenZeroAllocationsCredited_thenOldBucketsRetried(
        uint256 oldReward_,
        uint256 oldSeized_
    ) public {
        oldReward_ = bound(oldReward_, 0, type(uint256).max);
        oldSeized_ = bound(oldSeized_, 0, type(uint256).max - oldReward_);
        _deferSeizure(_token, _keeper, oldReward_, oldSeized_);
        _token.setTransferReverts(_keeper, false);
        _token.setTransferReverts(_treasury(), false);
        vm.prank(address(_core));
        _payout.creditSeizure(address(_token), _keeper, 0, 0);
        assertEq(_token.balanceOf(_keeper), oldReward_, "Zero new reward retries old reward");
        assertEq(
            _token.balanceOf(_treasury()),
            oldSeized_,
            "Zero new remainder retries old seizure"
        );
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-D01, BLCU-CREDIT-SEIZURE-L04, BLCU-CREDIT-SEIZURE-I01.
    function test_whenBothRecipientsAccept_thenBothBucketsPaid(
        uint256 reward_,
        uint256 seized_
    ) public {
        reward_ = bound(reward_, 0, type(uint256).max);
        seized_ = bound(seized_, 0, type(uint256).max - reward_);
        _creditSeizure(_token, _keeper, reward_, seized_);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
        assertEq(_token.balanceOf(_keeper), reward_, "Exact keeper allocation");
        assertEq(_token.balanceOf(_treasury()), seized_, "Exact Treasury allocation");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-D01.
    function test_givenKeeperBlocked_whenCredited_thenOnlyRewardDeferred() public {
        _token.setTransferReverts(_keeper, true);
        _token.mint(address(_payout), 50);
        _expectPayoutDeferred(_keeper, IBurnerLoansPayout.PayoutKind.SeizureReward, 30);
        _expectPayoutTransferred(_treasury(), IBurnerLoansPayout.PayoutKind.Seizure, 20);
        vm.prank(address(_core));
        _payout.creditSeizure(address(_token), _keeper, 30, 20);
        _assertBuckets(address(_token), _keeper, 0, 0, 30, 30);
        assertEq(_token.balanceOf(_treasury()), 20, "Treasury paid despite keeper failure");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-D01.
    function test_givenTreasuryBlocked_whenCredited_thenOnlySeizureDeferred() public {
        _token.setTransferReverts(_treasury(), true);
        _token.mint(address(_payout), 50);
        _expectPayoutTransferred(_keeper, IBurnerLoansPayout.PayoutKind.SeizureReward, 30);
        _expectPayoutDeferred(_treasury(), IBurnerLoansPayout.PayoutKind.Seizure, 20);
        vm.prank(address(_core));
        _payout.creditSeizure(address(_token), _keeper, 30, 20);
        _assertBuckets(address(_token), _keeper, 0, 20, 0, 20);
        assertEq(_token.balanceOf(_keeper), 30, "Keeper paid despite Treasury failure");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-D01.
    function test_givenBothBlocked_whenCredited_thenBothBucketsDeferred(bool overlap_) public {
        address keeper = overlap_ ? _treasury() : _keeper;
        _deferSeizure(_token, keeper, 30, 20);
        _assertBuckets(address(_token), keeper, 0, 20, 30, 50);
        assertEq(
            _token.balanceOf(address(_payout)),
            50,
            "Independent failed buckets remain backed even when recipients overlap"
        );
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-D01.
    function test_givenSharedRecipient_whenBothAccept_thenBothBucketsPaidOnce() public {
        _creditSeizure(_token, _treasury(), 30, 20);
        _assertBuckets(address(_token), _treasury(), 0, 0, 0, 0);
        assertEq(
            _token.balanceOf(_treasury()),
            50,
            "One recipient receives two distinct allocations"
        );
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-I01, BLCU-CREDIT-SEIZURE-L04.
    function test_givenAllocationBoundarySeeds_whenCredited_thenExactAmounts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenBothRecipientsAccept_thenBothBucketsPaid(0, 0);
        _restore(checkpoint);
        test_whenBothRecipientsAccept_thenBothBucketsPaid(1, 0);
        _restore(checkpoint);
        test_whenBothRecipientsAccept_thenBothBucketsPaid(0, 1);
        _restore(checkpoint);
        test_whenBothRecipientsAccept_thenBothBucketsPaid(type(uint256).max, 0);
        _restore(checkpoint);
        test_whenBothRecipientsAccept_thenBothBucketsPaid(0, type(uint256).max);
        _restore(checkpoint);
        test_givenOldBuckets_whenZeroAllocationsCredited_thenOldBucketsRetried(30, 20);
    }

    function _expectSeizureRejected(bytes memory reason_, address caller_) internal {
        bytes32 state = _ledgerDigest();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.creditSeizure(address(_token), _keeper, 1, 1);
        assertEq(_ledgerDigest(), state, "Rejected allocation leaves custody and indexes intact");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-I01.
    function test_givenExistingBuckets_whenNewRewardZero_thenBothOldBucketsRetried() public {
        _deferSeizure(_token, _keeper, 3, 4);
        _token.setTransferReverts(_keeper, false);
        _token.setTransferReverts(_treasury(), false);
        _creditSeizure(_token, _keeper, 0, 11);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
        assertEq(_token.balanceOf(_keeper), 3, "Old reward still retried");
        assertEq(_token.balanceOf(_treasury()), 15, "Old plus new seizure paid");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-I01.
    function test_givenExistingBuckets_whenNewSeizureZero_thenBothOldBucketsRetried() public {
        _deferSeizure(_token, _keeper, 3, 4);
        _token.setTransferReverts(_keeper, false);
        _token.setTransferReverts(_treasury(), false);
        _creditSeizure(_token, _keeper, 7, 0);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
        assertEq(_token.balanceOf(_keeper), 10, "Old plus new reward paid");
        assertEq(_token.balanceOf(_treasury()), 4, "Old seizure still retried");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-N02.
    function test_whenAllocationSumOverflows_thenExactError(
        uint256 reward_,
        uint256 remainder_
    ) public {
        reward_ = bound(reward_, 1, type(uint256).max);
        remainder_ = bound(remainder_, type(uint256).max - reward_ + 1, type(uint256).max);
        bytes32 state = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_AmountOverflow.selector,
                reward_,
                remainder_
            )
        );
        vm.prank(address(_core));
        _payout.creditSeizure(address(_token), _keeper, reward_, remainder_);
        assertEq(
            _ledgerDigest(),
            state,
            "Allocation overflow cannot create liability or move custody"
        );
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-N03.
    function test_givenExistingReserve_whenTotalOverflows_thenExactError(
        uint256 pending_,
        uint256 receipt_,
        uint256 reward_
    ) public {
        pending_ = bound(pending_, 1, type(uint256).max);
        receipt_ = bound(receipt_, type(uint256).max - pending_ + 1, type(uint256).max);
        reward_ = bound(reward_, 0, receipt_);
        _deferFee(_token, pending_);
        bytes32 state = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_AmountOverflow.selector,
                pending_,
                receipt_
            )
        );
        vm.prank(address(_core));
        _payout.creditSeizure(address(_token), _keeper, reward_, receipt_ - reward_);
        assertEq(
            _ledgerDigest(),
            state,
            "Aggregate overflow restores existing reserves and indexes"
        );
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-L05.
    function test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _deactivatePayoutWithBrokenRoles(caller_, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.creditSeizure(address(_token), _keeper, 1, 1);
        assertEq(_ledgerDigest(), state, "Inactivity rejects before authority or mutation");
    }

    // Scenarios: BLCU-CREDIT-SEIZURE-L06.
    function test_givenActivePausedPayout_whenNonCoreCredits_thenEnablementWins()
        public
        givenPendingBuckets
    {
        _payout.disable("");
        bytes32 state = _ledgerDigest();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_recipient);
        _payout.creditSeizure(address(_token), _keeper, 1, 1);
        assertEq(_ledgerDigest(), state, "Pause rejects before Core caller authentication");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
