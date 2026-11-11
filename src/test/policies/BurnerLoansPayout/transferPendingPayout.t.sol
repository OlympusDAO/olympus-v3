// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";

// Libraries
import {BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {BurnerLoansYieldClaimerTask} from "src/policies/burnerloans/BurnerLoansYieldClaimerTask.sol";
import {GasSensitivePayoutToken} from "src/test/mocks/GasSensitivePayoutToken.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";

contract BurnerLoansPayoutTransferPendingPayoutTest is BurnerLoansPayoutTest {
    // Scenarios: BLCUTRY-I03.
    function test_whenRecipientIsZero_reverts(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, true, enabled_);
        bytes32 beforeState = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        _payout.transferPendingPayout(address(_token), address(0));
        assertEq(_ledgerDigest(), beforeState, "Zero retry recipient cannot consume any bucket");
    }

    // Scenarios: BLCUTRY-I02.
    function test_givenProtocolRouteBecomesPayout_whenRetried_reverts(address caller_) public {
        _deferFee(_token, 10);
        _mockTreasuryRecipient(address(_payout));
        bytes32 beforeState = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
                address(_payout)
            )
        );
        vm.prank(caller_);
        _payout.transferPendingPayout(address(_token), address(_payout));
        assertEq(
            _ledgerDigest(),
            beforeState,
            "Route drift to self cannot discharge the old protocol obligation"
        );
    }

    // Scenarios: BLCUTRY-P13, BLCUTRY-P14, BLCUTRY-T02.
    function test_givenReferralPending_whenRetriedAfterPauseAndReplacement(
        address caller_,
        bool paused_,
        bool replaced_
    ) public {
        _risk.setReferrerAllowed(_keeper, true);
        _risk.setReferralFeeBps(10_000);
        _token.setTransferReverts(_keeper, true);
        _creditReferral(_token, 0, _keeper, 25);
        _risk.setReferrerAllowed(_keeper, false);
        _risk.setReferralFeeBps(0);
        if (paused_) _payout.disable("");
        if (replaced_) _core.setPayout(address(_otherPayout));
        vm.mockCallRevert(address(_risk), bytes(""), hex"deadbeef");
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            0,
            "Failed retry retains original reward"
        );
        _assertReferral(address(_token), _keeper, 25);
        _token.setTransferReverts(_keeper, false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            25,
            "Permissionless retired/paused retry pays original recipient"
        );
        assertEq(_token.balanceOf(_keeper), 25, "Original referrer paid once");
        _assertReferral(address(_token), _keeper, 0);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
        vm.recordLogs();
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            0,
            "Repeated retry pays nothing"
        );
        assertEq(
            vm.getRecordedLogs().length,
            0,
            "Retry emits no new accrual or payment after clearing"
        );
    }

    // Scenarios: BLCUTRY-P15.
    function test_givenTwoReferrers_whenOtherIdentityRetries(address caller_) public {
        _token.setTransferReverts(_keeper, true);
        _creditReferral(_token, 0, _keeper, 25);
        _token.setTransferReverts(_secondKeeper, true);
        _creditReferral(_token, 0, _secondKeeper, 7);
        _risk.setReferrerAllowed(_keeper, false);
        _risk.setReferrerAllowed(_secondKeeper, true);
        _token.setTransferReverts(_secondKeeper, false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _secondKeeper),
            7,
            "Different recipient collects only its own reward"
        );
        _assertReferral(address(_token), _keeper, 25);
        _assertReferral(address(_token), _secondKeeper, 0);
        assertEq(
            _payout.pendingRecipientAmount(address(_token), _keeper),
            25,
            "Ordinary getter includes original referral liability"
        );
    }

    // Scenarios: BLCUTRY-P14.
    function test_givenFailedReferral_whenPayoutReEnabledAndReactivated(address caller_) public {
        _token.setTransferReverts(_keeper, true);
        _creditReferral(_token, 0, _keeper, 25);
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            0,
            "Initial rejected delivery retains entitlement"
        );
        _payout.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_payout));
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        _payout.reEnable();
        _assertReferral(address(_token), _keeper, 25);
        _token.setTransferReverts(_keeper, false);
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            25,
            "Restored lifecycle permits exact original payment"
        );
        _assertReferral(address(_token), _keeper, 0);
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            0,
            "Restoration cannot duplicate payment"
        );
    }

    // Scenarios: BLCUTRY-N01.
    function test_givenReferralMaximum_whenRetried(address caller_) public {
        _token.setTransferReverts(_keeper, true);
        _creditReferral(_token, 0, _keeper, type(uint256).max);
        _token.setTransferReverts(_keeper, false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            type(uint256).max,
            "Maximum referral transfers without overflow"
        );
        _assertReferral(address(_token), _keeper, 0);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
    }

    // Scenarios: BLCUTRY-N01.
    function test_givenOneReferralUnit_whenRetried(address caller_) public {
        _token.setTransferReverts(_keeper, true);
        _creditReferral(_token, 0, _keeper, 1);
        _token.setTransferReverts(_keeper, false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            1,
            "One raw reward unit delivered exactly"
        );
        _assertReferral(address(_token), _keeper, 0);
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
    }

    // Scenarios: BLCUTRY-P17.
    function test_givenReferralAndKeeperOverlap_whenRetried(address caller_) public {
        _seedBuckets(20, 30, 10, _keeper);
        _creditReferral(_token, 0, _keeper, 40);
        _token.setTransferReverts(_keeper, false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            50,
            "Keeper10 plus referral40"
        );
        _assertBuckets(address(_token), _keeper, 20, 30, 0, 50);
        _assertReferral(address(_token), _keeper, 0);
    }

    // Scenarios: BLCUTRY-P18.
    function test_givenReferralAndFeeOverlap_whenRetried(address caller_) public {
        _useDistributor();
        _seedBuckets(20, 30, 10, _keeper);
        address recipient = address(_distributor);
        _creditReferral(_token, 0, recipient, 40);
        _token.setTransferReverts(recipient, false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), recipient),
            60,
            "Protocol20 plus referral40"
        );
        _assertBuckets(address(_token), _keeper, 0, 30, 10, 40);
        _assertReferral(address(_token), recipient, 0);
    }

    // Scenarios: BLCUTRY-P19.
    function test_givenReferralAndTreasuryOverlap_whenRetried(address caller_) public {
        _useDistributor();
        _seedBuckets(20, 30, 10, _keeper);
        _creditReferral(_token, 0, _treasury(), 40);
        _token.setTransferReverts(_treasury(), false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _treasury()),
            70,
            "Seized30 plus referral40"
        );
        _assertBuckets(address(_token), _keeper, 20, 0, 10, 30);
        _assertReferral(address(_token), _treasury(), 0);
    }

    // Scenarios: BLCUTRY-P20.
    function test_givenAllCategoriesAndReferralOverlap_whenRetried(address caller_) public {
        address recipient = _treasury();
        _seedBuckets(20, 30, 10, recipient);
        _creditReferral(_token, 0, recipient, 40);
        _token.setTransferReverts(recipient, false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), recipient),
            100,
            "All four categories paid exactly once"
        );
        _assertBuckets(address(_token), recipient, 0, 0, 0, 0);
        _assertReferral(address(_token), recipient, 0);
        assertEq(
            _payout.getPendingPayoutRecipients(address(_token)).length,
            0,
            "All recipient indexes cleared"
        );
    }

    // Scenarios: BLCUTRY-T03.
    function test_givenAllCategoriesAndAlternatingFailures_whenRetried(address caller_) public {
        address recipient = _treasury();
        _seedBuckets(20, 30, 10, recipient);
        _creditReferral(_token, 0, recipient, 40);
        _token.setTransferReverts(recipient, false);
        vm.mockCall(
            address(_token),
            abi.encodeCall(_token.transfer, (recipient, uint256(30))),
            abi.encode(false)
        );
        vm.mockCall(
            address(_token),
            abi.encodeCall(_token.transfer, (recipient, uint256(40))),
            abi.encode(false)
        );
        _expectPayoutTransferred(recipient, IBurnerLoansPayout.PayoutKind.Fee, 20);
        _expectPayoutDeferred(recipient, IBurnerLoansPayout.PayoutKind.Seizure, 30);
        _expectPayoutTransferred(recipient, IBurnerLoansPayout.PayoutKind.SeizureReward, 10);
        _expectPayoutDeferred(recipient, IBurnerLoansPayout.PayoutKind.Referral, 40);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), recipient),
            30,
            "Fee20 and keeper10 paid in established order"
        );
        _assertBuckets(address(_token), recipient, 0, 30, 0, 70);
        _assertReferral(address(_token), recipient, 40);
    }

    // Scenarios: BLCUTRY-P09.
    function test_givenAllBucketsOverlap_whenRetiredPausedPayoutClaims_thenEveryBucketPaidOnce(
        address caller_
    ) public {
        address recipient = _treasury();
        _seedBuckets(10, 20, 30, recipient);
        (uint256 fee, , uint256 seized, , uint256 total) = _payout.pendingAmounts(address(_token));
        assertEq(fee, 10, "Pending fee bucket");
        assertEq(seized, 20, "Pending Treasury bucket");
        assertEq(total, 60, "10 fee + 20 seizure + 30 keeper = 60 raw units");
        _core.setPayout(address(_otherPayout));
        _setState(_payout, true, false);
        _token.setTransferReverts(recipient, false);
        vm.prank(caller_);
        uint256 paid = _payout.transferPendingPayout(address(_token), recipient);
        assertEq(paid, 60, "All three entitlements paid once");
        assertEq(_token.balanceOf(recipient), 60, "Recipient receives sum of distinct buckets");
        (fee, , seized, , total) = _payout.pendingAmounts(address(_token));
        assertEq(fee, 0, "Fee cleared");
        assertEq(seized, 0, "Seizure cleared");
        assertEq(total, 0, "Aggregate cleared");
        assertEq(_payout.getPendingKeepers(address(_token)).length, 0, "Keeper index cleared");
        assertEq(_payout.getPendingPayoutTokens().length, 0, "Token index cleared");
        assertEq(
            _payout.transferPendingPayout(address(_token), recipient),
            0,
            "Second claim cannot pay twice"
        );
    }

    struct RetryAllocation {
        uint256 fee;
        uint256 seized;
        uint256 reward;
        address keeper;
        address recipient;
        uint256 paid;
        uint256 feeLeft;
        uint256 seizedLeft;
        uint256 rewardLeft;
        uint256 totalLeft;
    }

    // Scenarios: BLCUTRY-P01.
    function test_givenNoEntitlement_whenRetried_thenNoCallsOrEvents(address caller_) public {
        bytes32 state = _ledgerDigest();
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            0,
            "Empty retry returns zero"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Empty retry emits no event");
        assertEq(_token.transferCallCount(), 0, "No transfer attempted");
        assertEq(_ledgerDigest(), state, "No-op preserves state");
    }

    function _assertRetry(RetryAllocation memory a_, address caller_) internal {
        _seedBuckets(a_.fee, a_.seized, a_.reward, a_.keeper);
        _token.setTransferReverts(a_.recipient, false);
        uint256 beforeBalance = _token.balanceOf(a_.recipient);
        uint256 calls = _token.transferCallCount();
        bytes32 other = _bucketDigest(address(_otherToken));
        bytes32 retired = _retiredDigest();
        assertEq(
            _payout.pendingRecipientAmount(address(_token), a_.recipient),
            a_.paid,
            "Current getter matches independent eligible buckets"
        );
        if (a_.fee != a_.feeLeft)
            _expectPayoutTransferred(
                a_.recipient,
                IBurnerLoansPayout.PayoutKind.Fee,
                a_.fee - a_.feeLeft
            );
        if (a_.seized != a_.seizedLeft)
            _expectPayoutTransferred(
                a_.recipient,
                IBurnerLoansPayout.PayoutKind.Seizure,
                a_.seized - a_.seizedLeft
            );
        if (a_.reward != a_.rewardLeft)
            _expectPayoutTransferred(
                a_.recipient,
                IBurnerLoansPayout.PayoutKind.SeizureReward,
                a_.reward - a_.rewardLeft
            );
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), a_.recipient),
            a_.paid,
            "Return sum of separately paid buckets"
        );
        _assertBuckets(
            address(_token),
            a_.keeper,
            a_.feeLeft,
            a_.seizedLeft,
            a_.rewardLeft,
            a_.totalLeft
        );
        assertEq(
            _token.balanceOf(a_.recipient),
            beforeBalance + a_.paid,
            "Recipient gets each eligible bucket once"
        );
        assertEq(
            _token.balanceOf(address(_payout)),
            a_.totalLeft,
            "Unpaid liabilities retain custody"
        );
        uint256 paidKinds = (a_.fee != a_.feeLeft ? 1 : 0) +
            (a_.seized != a_.seizedLeft ? 1 : 0) +
            (a_.reward != a_.rewardLeft ? 1 : 0);
        assertEq(
            _token.transferCallCount(),
            calls + paidKinds,
            "One actual transfer per paid kind"
        );
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), a_.recipient),
            0,
            "Second retry cannot pay twice"
        );
        assertEq(_bucketDigest(address(_otherToken)), other, "Other token unchanged");
        assertEq(_retiredDigest(), retired, "Other Payout unchanged");
    }

    // Scenarios: BLCUTRY-P12.
    function test_givenSharedRecipientAndOtherKeeper_whenRetried_thenOnlySelectedClaimsPaid(
        address caller_
    ) public {
        _seedBuckets(10, 20, 30, _treasury());
        _deferSeizure(_token, _secondKeeper, 7, 0);
        _token.setTransferReverts(_treasury(), false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _treasury()),
            60,
            "Three eligible buckets paid once"
        );
        _assertBuckets(address(_token), _treasury(), 0, 0, 0, 7);
        assertEq(
            _subject.keeperReward(address(_token), _secondKeeper),
            7,
            "Unrelated original keeper unchanged"
        );
        assertTrue(
            _subject.hasPendingKeeper(address(_token), _secondKeeper),
            "Unrelated keeper still indexed"
        );
        assertEq(_token.balanceOf(address(_payout)), 7, "Other claim remains backed");
        address[] memory recipients = _payout.getPendingPayoutRecipients(address(_token));
        assertEq(recipients.length, 1, "Only second keeper remains in read-back");
        assertEq(recipients[0], _secondKeeper, "Original identity retained");
    }

    // Scenarios: BLCUTRY-T01.
    function test_givenFirstSharedBucketFails_whenRetried_thenLaterBucketsStillPaid(
        address caller_
    ) public {
        _seedBuckets(10, 20, 30, _treasury());
        _token.setTransferReverts(_treasury(), false);
        vm.mockCallRevert(
            address(_token),
            abi.encodeCall(_token.transfer, (_treasury(), uint256(10))),
            abi.encodeWithSelector(
                MockRevertingTransferToken.TransferReverted.selector,
                _treasury()
            )
        );
        _expectPayoutDeferred(_treasury(), IBurnerLoansPayout.PayoutKind.Fee, 10);
        _expectPayoutTransferred(_treasury(), IBurnerLoansPayout.PayoutKind.Seizure, 20);
        _expectPayoutTransferred(_treasury(), IBurnerLoansPayout.PayoutKind.SeizureReward, 30);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _treasury()),
            50,
            "Only successful kinds count toward return"
        );
        _assertBuckets(address(_token), _treasury(), 10, 0, 0, 10);
        assertEq(_token.balanceOf(_treasury()), 50, "Failure does not roll back other payouts");
    }

    // Scenarios: BLCUTRY-T01.
    function test_givenSecondSharedBucketReturnsFalse_whenRetried_thenOnlySeizureRetained(
        address caller_
    ) public {
        _seedBuckets(10, 20, 30, _treasury());
        _token.setTransferReverts(_treasury(), false);
        vm.mockCall(
            address(_token),
            abi.encodeCall(_token.transfer, (_treasury(), uint256(20))),
            abi.encode(false)
        );
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _treasury()),
            40,
            "False seized payout does not block fee or reward"
        );
        _assertBuckets(address(_token), _treasury(), 0, 20, 0, 20);
        assertEq(_token.balanceOf(_treasury()), 40, "Only paid kinds delivered");
    }

    // Scenarios: BLCUTRY-T01.
    function test_givenLastSharedBucketFails_whenRetried_thenOnlyKeeperRetained(
        address caller_
    ) public {
        _seedBuckets(10, 20, 30, _treasury());
        _token.setTransferReverts(_treasury(), false);
        vm.mockCallRevert(
            address(_token),
            abi.encodeCall(_token.transfer, (_treasury(), uint256(30))),
            abi.encodeWithSelector(
                MockRevertingTransferToken.TransferReverted.selector,
                _treasury()
            )
        );
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _treasury()),
            30,
            "Fee and seized collateral paid"
        );
        _assertBuckets(address(_token), _treasury(), 0, 0, 30, 30);
        assertEq(_token.balanceOf(_treasury()), 30, "Failed reward stays owed");
    }

    // Scenarios: BLCUTRY-P03.
    function test_givenTreasuryReplacement_whenRetried_thenGenericBucketsFollowLiveModule(
        address caller_
    ) public {
        address old = _treasury();
        _seedBuckets(10, 20, 30, old);
        OlympusTreasury replacement = new OlympusTreasury(_kernel);
        _kernel.executeAction(Actions.UpgradeModule, address(replacement));
        assertEq(_payout.treasury(), address(replacement), "Getter resolves current Kernel module");
        _token.setTransferReverts(old, false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), old),
            30,
            "Old Treasury keeps only its fixed keeper reward"
        );
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), address(replacement)),
            30,
            "New Treasury receives generic fee and seized backing"
        );
        _assertBuckets(address(_token), old, 0, 0, 0, 0);
        assertEq(_token.balanceOf(old), 30, "Keeper reward never migrates");
        assertEq(
            _token.balanceOf(address(replacement)),
            30,
            "Protocol liabilities follow live route"
        );
    }

    // Scenarios: BLCUTRY-P03.
    function test_givenFeeFlagRotation_whenRetried_thenFeeMovesAndKeeperStays(
        address caller_
    ) public {
        _useDistributor();
        address old = address(_distributor);
        _seedBuckets(10, 20, 30, old);
        _payout.setSendFeesToDistributor(false);
        _token.setTransferReverts(old, false);
        _token.setTransferReverts(_treasury(), false);
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), old),
            30,
            "Former fee route retains its own keeper reward"
        );
        vm.prank(caller_);
        assertEq(
            _payout.transferPendingPayout(address(_token), _treasury()),
            30,
            "Generic fee follows flag rotation"
        );
        _assertBuckets(address(_token), old, 0, 0, 0, 0);
    }

    // Scenarios: BLCUTRY-P02.
    function test_givenFeeOnly_whenRetried_thenExactEligibleBuckets(address caller_) public {
        RetryAllocation memory allocation = RetryAllocation({
            fee: 10,
            seized: 0,
            reward: 0,
            keeper: _keeper,
            recipient: _treasury(),
            paid: 10,
            feeLeft: 0,
            seizedLeft: 0,
            rewardLeft: 0,
            totalLeft: 0
        });
        _assertRetry(allocation, caller_);
    }

    // Scenarios: BLCUTRY-P04.
    function test_givenSeizureOnly_whenRetried_thenExactEligibleBuckets(address caller_) public {
        RetryAllocation memory allocation = RetryAllocation({
            fee: 0,
            seized: 20,
            reward: 0,
            keeper: _keeper,
            recipient: _treasury(),
            paid: 20,
            feeLeft: 0,
            seizedLeft: 0,
            rewardLeft: 0,
            totalLeft: 0
        });
        _assertRetry(allocation, caller_);
    }

    // Scenarios: BLCUTRY-P05.
    function test_givenKeeperOnly_whenRetried_thenExactEligibleBuckets(address caller_) public {
        RetryAllocation memory allocation = RetryAllocation({
            fee: 0,
            seized: 0,
            reward: 30,
            keeper: _keeper,
            recipient: _keeper,
            paid: 30,
            feeLeft: 0,
            seizedLeft: 0,
            rewardLeft: 0,
            totalLeft: 0
        });
        _assertRetry(allocation, caller_);
    }

    // Scenarios: BLCUTRY-P06.
    function test_givenFeeAndSeizureOverlap_whenRetried_thenExactEligibleBuckets(
        address caller_
    ) public {
        RetryAllocation memory allocation = RetryAllocation({
            fee: 10,
            seized: 20,
            reward: 0,
            keeper: _keeper,
            recipient: _treasury(),
            paid: 30,
            feeLeft: 0,
            seizedLeft: 0,
            rewardLeft: 0,
            totalLeft: 0
        });
        _assertRetry(allocation, caller_);
    }

    // Scenarios: BLCUTRY-P07.
    function test_givenFeeAndKeeperOverlap_whenRetried_thenExactEligibleBuckets(
        address caller_
    ) public {
        _useDistributor();
        RetryAllocation memory allocation = RetryAllocation({
            fee: 10,
            seized: 0,
            reward: 30,
            keeper: address(_distributor),
            recipient: address(_distributor),
            paid: 40,
            feeLeft: 0,
            seizedLeft: 0,
            rewardLeft: 0,
            totalLeft: 0
        });
        _assertRetry(allocation, caller_);
    }

    // Scenarios: BLCUTRY-P08.
    function test_givenSeizureAndKeeperOverlap_whenRetried_thenExactEligibleBuckets(
        address caller_
    ) public {
        RetryAllocation memory allocation = RetryAllocation({
            fee: 0,
            seized: 20,
            reward: 30,
            keeper: _treasury(),
            recipient: _treasury(),
            paid: 50,
            feeLeft: 0,
            seizedLeft: 0,
            rewardLeft: 0,
            totalLeft: 0
        });
        _assertRetry(allocation, caller_);
    }

    // Scenarios: BLCUTRY-P09.
    function test_givenAllBucketsOverlap_whenRetried_thenExactEligibleBuckets(
        address caller_
    ) public {
        RetryAllocation memory allocation = RetryAllocation({
            fee: 10,
            seized: 20,
            reward: 30,
            keeper: _treasury(),
            recipient: _treasury(),
            paid: 60,
            feeLeft: 0,
            seizedLeft: 0,
            rewardLeft: 0,
            totalLeft: 0
        });
        _assertRetry(allocation, caller_);
    }

    // Scenarios: BLCUTRY-P10.
    function test_givenAllRoutesDistinct_whenRetried_thenExactEligibleBuckets(
        address caller_
    ) public {
        _useDistributor();
        RetryAllocation memory allocation = RetryAllocation({
            fee: 10,
            seized: 20,
            reward: 30,
            keeper: _keeper,
            recipient: _keeper,
            paid: 30,
            feeLeft: 10,
            seizedLeft: 20,
            rewardLeft: 0,
            totalLeft: 30
        });
        _assertRetry(allocation, caller_);
    }

    // Scenarios: BLCUTRY-P11.
    function test_givenUnrelatedRecipient_whenRetried_thenExactEligibleBuckets(
        address caller_
    ) public {
        _useDistributor();
        RetryAllocation memory allocation = RetryAllocation({
            fee: 10,
            seized: 20,
            reward: 30,
            keeper: _keeper,
            recipient: _destination,
            paid: 0,
            feeLeft: 10,
            seizedLeft: 20,
            rewardLeft: 30,
            totalLeft: 60
        });
        _assertRetry(allocation, caller_);
    }

    function test_givenTransferNeedsMoreThanFormerGasCap_whenRetried_thenDelivered() public {
        GasSensitivePayoutToken token = new GasSensitivePayoutToken();
        token.mint(address(_payout), 10);
        token.setNeedsMoreGas(true);
        vm.prank(address(_core));
        _payout.creditFee{gas: 180_000}(address(token), 10, address(0), 0);
        _assertBuckets(address(token), _keeper, 10, 0, 0, 10);
        assertEq(
            _payout.transferPendingPayout(address(token), _treasury()),
            10,
            "Uncapped retry supports a token requiring over 200,000 gas"
        );
        _assertBuckets(address(token), _keeper, 0, 0, 0, 0);
        assertEq(token.balanceOf(_treasury()), 10, "Actual delivery succeeds");
    }

    function test_givenPendingRewardAndFee_whenHeartTaskRuns_thenOnlyDirectRetryPays() public {
        _price.setPrice(address(_token), 1e18);
        _admit(address(_token));
        _seedBuckets(10, 0, 30, _keeper);
        BurnerLoansYieldClaimerTask claimer = new BurnerLoansYieldClaimerTask(
            _kernel,
            address(_core),
            2_000_000
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(claimer));
        _rolesAdmin.grantRole(BL_YIELD_CLAIMER_ROLE, address(claimer));
        _rolesAdmin.grantRole(HEART_ROLE, _recipient);
        claimer.enable("");
        _token.setTransferReverts(_keeper, false);
        _token.setTransferReverts(_treasury(), false);
        bytes32 state = _ledgerDigest();
        vm.prank(_recipient);
        claimer.execute();
        assertEq(
            _ledgerDigest(),
            state,
            "Heart yield work does not sweep fee or keeper liabilities"
        );
        assertEq(
            _payout.transferPendingPayout(address(_token), _keeper),
            30,
            "Original keeper remains payable directly"
        );
        assertEq(
            _payout.transferPendingPayout(address(_token), _treasury()),
            10,
            "Fee remains payable directly"
        );
        _assertBuckets(address(_token), _keeper, 0, 0, 0, 0);
    }

    // Scenarios: BLCUTRY-L01.
    function test_givenPayoutInactive_whenRetried_reverts(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, false, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.transferPendingPayout(address(_token), _keeper);
        assertEq(_ledgerDigest(), state, "Inactive retry preserves every entitlement");
    }

    // Scenarios: BLCUTRY-L02.
    function test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _deactivatePayoutWithBrokenRoles(caller_, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.transferPendingPayout(address(_token), _keeper);
        assertEq(_ledgerDigest(), state, "Inactivity rejects before authority or mutation");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
