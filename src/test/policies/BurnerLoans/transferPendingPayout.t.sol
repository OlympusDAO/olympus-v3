// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {GasSensitivePayoutToken} from "src/test/mocks/GasSensitivePayoutToken.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {BurnerLoansYieldClaimer} from "src/policies/BurnerLoansYieldClaimer.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Setup calls intentionally ignore return values after verifying resulting balances and debts.
// Scenario-specific values remain inline for accounting clarity.
// forge-lint: disable-start(unused-return,literal-instead-of-constant)

contract BurnerLoansTransferPendingPayoutTest is BurnerLoansBorrowTestBase {
    struct CallbackCase {
        uint8 bucket;
        uint256 fee;
        uint256 seizure;
        uint256 reward;
        uint256 leading;
        uint256 target;
    }

    function _seedOverlappingBuckets(
        MockRevertingTransferToken token_,
        uint8 mask_,
        uint256 fee_,
        uint256 seizure_,
        uint256 reward_
    ) internal {
        token_.setTransferReverts(address(trsry), true);
        if ((mask_ & 1) != 0) {
            token_.mint(alice, fee_);
            vm.prank(alice);
            token_.approve(address(burnerLoans), fee_);
            burnerLoans.recordPendingFeeForTest(address(token_), alice, address(trsry), fee_);
        }
        if ((mask_ & 2) != 0) {
            token_.mint(address(burnerLoans), seizure_);
            burnerLoans.recordPendingSeizedCollateralForTest(
                address(token_),
                address(trsry),
                seizure_
            );
        }
        if ((mask_ & 4) != 0) {
            token_.mint(address(burnerLoans), reward_);
            burnerLoans.recordPendingSeizureRewardForTest(address(token_), address(trsry), reward_);
        }
        token_.setTransferReverts(address(trsry), false);
    }

    function _expectOverlappingPayoutEvents(
        MockRevertingTransferToken token_,
        uint8 mask_,
        uint256 fee_,
        uint256 seizure_,
        uint256 reward_
    ) internal {
        if ((mask_ & 1) != 0) {
            vm.expectEmit(true, true, true, true, address(burnerLoans));
            emit IBurnerLoans.PayoutTransferred(
                address(token_),
                address(trsry),
                IBurnerLoans.PayoutKind.Fee,
                fee_
            );
        }
        if ((mask_ & 2) != 0) {
            vm.expectEmit(true, true, true, true, address(burnerLoans));
            emit IBurnerLoans.PayoutTransferred(
                address(token_),
                address(trsry),
                IBurnerLoans.PayoutKind.Seizure,
                seizure_
            );
        }
        if ((mask_ & 4) != 0) {
            vm.expectEmit(true, true, true, true, address(burnerLoans));
            emit IBurnerLoans.PayoutTransferred(
                address(token_),
                address(trsry),
                IBurnerLoans.PayoutKind.SeizureReward,
                reward_
            );
        }
    }

    function _selectedBucketSum(
        uint8 mask_,
        uint256 fee_,
        uint256 seizure_,
        uint256 reward_
    ) internal pure returns (uint256) {
        return
            ((mask_ & 1) != 0 ? fee_ : 0) +
            ((mask_ & 2) != 0 ? seizure_ : 0) +
            ((mask_ & 4) != 0 ? reward_ : 0);
    }

    function _selectedBucketCount(uint8 mask_) internal pure returns (uint256) {
        return ((mask_ & 1) != 0 ? 1 : 0) + ((mask_ & 2) != 0 ? 1 : 0) + ((mask_ & 4) != 0 ? 1 : 0);
    }

    // Scenarios: BLTRY-P02
    function test_givenPendingFee_retryPaysEveryQuantityToCurrentRoute(
        bool sendFeesToDistributor_,
        bool useMaximum_,
        uint256 amountSeed_,
        address caller_
    ) public {
        uint256 amount = useMaximum_
            ? type(uint256).max
            : bound(amountSeed_, 1, type(uint256).max - 1);
        MockRevertingTransferToken token = new MockRevertingTransferToken(_collateralDecimals());
        address recipient = _configureFeeRecipientForTest(sendFeesToDistributor_, address(token));
        token.setTransferReverts(recipient, true);
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(burnerLoans), amount);
        burnerLoans.recordPendingFeeForTest(address(token), alice, recipient, amount);
        token.setTransferReverts(recipient, false);

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(token),
            recipient,
            IBurnerLoans.PayoutKind.Fee,
            amount
        );
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(token), recipient),
            amount,
            "retry returns exact fee"
        );

        assertEq(token.balanceOf(recipient), amount, "current route receives exact fee");
        assertEq(burnerLoans.pendingFeeForTest(address(token)), 0, "fee bucket clears");
        assertEq(burnerLoans.totalPendingForTest(address(token)), 0, "reserve clears");
        assertEq(burnerLoans.pendingPayout(address(token), recipient), 0, "recipient debt clears");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "token index clears");
        assertEq(
            burnerLoans.getPendingPayoutRecipients(address(token)).length,
            0,
            "recipient index clears"
        );
    }

    // Scenarios: BLTRY-P04
    function test_givenOverlappingBuckets_retryPaysEachSelectedBucketInOrder(
        uint8 maskSeed_,
        uint96 feeSeed_,
        uint96 seizureSeed_,
        uint96 rewardSeed_,
        address caller_
    ) public {
        uint8[4] memory masks = [uint8(3), 5, 6, 7];
        uint8 mask = masks[bound(maskSeed_, 0, masks.length - 1)];
        uint256 fee = bound(feeSeed_, 1, type(uint96).max);
        uint256 seizure = bound(seizureSeed_, 1, type(uint96).max);
        uint256 reward = bound(rewardSeed_, 1, type(uint96).max);
        MockRevertingTransferToken token = new MockRevertingTransferToken(_collateralDecimals());
        MockRevertingTransferToken otherToken = new MockRevertingTransferToken(
            _collateralDecimals()
        );
        _seedOverlappingBuckets(token, mask, fee, seizure, reward);
        uint256 unrelated = 19;
        otherToken.setTransferReverts(alice, true);
        otherToken.mint(address(burnerLoans), unrelated);
        burnerLoans.recordPendingSeizureRewardForTest(address(otherToken), alice, unrelated);

        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(token));
        assertEq(recipients.length, 1, "overlapping recipient is listed once");
        assertEq(recipients[0], address(trsry), "Treasury is the shared recipient");
        _expectOverlappingPayoutEvents(token, mask, fee, seizure, reward);
        uint256 expected = _selectedBucketSum(mask, fee, seizure, reward);
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(token), address(trsry)),
            expected,
            "retry returns exact selected sum"
        );

        uint256 expectedCalls = _selectedBucketCount(mask);
        assertEq(token.transferCallCount(), expectedCalls, "one transfer per selected bucket");
        assertEq(token.balanceOf(address(trsry)), expected, "recipient receives exact sum");
        assertEq(burnerLoans.totalPendingForTest(address(token)), 0, "selected token clears");
        assertEq(
            burnerLoans.pendingSeizureRewardForTest(address(otherToken), alice),
            unrelated,
            "unrelated reward is unchanged"
        );
        assertEq(
            burnerLoans.totalPendingForTest(address(otherToken)),
            unrelated,
            "unrelated reserve is unchanged"
        );
        assertEq(burnerLoans.getPendingPayoutTokens().length, 1, "only unrelated token remains");
    }

    // Scenarios: BLTRY-P01, BLTRY-P13
    function test_givenNoEntitlement_whenAnyCallerRetries_returnsZero(
        address caller_,
        address unrelatedRecipient_
    ) public {
        vm.assume(unrelatedRecipient_ != address(trsry));
        vm.assume(unrelatedRecipient_ != address(0));
        address unknownContract = address(new ReentrantFeeToken());
        address unknownEoa = makeAddr("unknown token EOA");

        vm.startPrank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(0), unrelatedRecipient_),
            0,
            "zero token has no payout"
        );
        assertEq(
            burnerLoans.transferPendingPayout(unknownEoa, unrelatedRecipient_),
            0,
            "EOA token has no payout"
        );
        assertEq(
            burnerLoans.transferPendingPayout(unknownContract, unrelatedRecipient_),
            0,
            "unknown contract has no payout"
        );
        assertEq(
            burnerLoans.transferPendingPayout(address(usds), address(0)),
            0,
            "zero recipient has no payout"
        );
        assertEq(
            burnerLoans.transferPendingPayout(address(usds), unrelatedRecipient_),
            0,
            "unrelated recipient has no payout"
        );
        vm.stopPrank();

        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "no token is indexed");
        assertEq(
            burnerLoans.getPendingPayoutRecipients(address(usds)).length,
            0,
            "no recipient is indexed"
        );
    }

    // Scenarios: BLTRY-L01, BLTRY-L02, BLTRY-L03
    function test_givenPositivePending_whenDisabledAndInactive_viewsRemainReadable(
        address caller_,
        uint128 amount_
    ) public {
        uint256 amount = bound(amount_, 1, type(uint128).max);
        MockRevertingTransferToken tokenImplementation = new MockRevertingTransferToken(
            _collateralDecimals()
        );
        vm.etch(address(usds), address(tokenImplementation).code);
        MockRevertingTransferToken liveToken = MockRevertingTransferToken(address(usds));
        liveToken.mint(address(burnerLoans), amount);
        liveToken.setTransferReverts(alice, true);
        burnerLoans.recordPendingSeizureRewardForTest(address(usds), alice, amount);

        _disableBurnerLoans(admin);

        vm.prank(caller_);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.transferPendingPayout(address(usds), alice);
        _assertSinglePendingReward(amount);

        _deactivatePolicy(address(burnerLoans));

        vm.prank(caller_);
        vm.expectRevert(IBurnerLoans.BurnerLoans_PolicyInactive.selector);
        burnerLoans.transferPendingPayout(address(usds), alice);
        _assertSinglePendingReward(amount);
    }

    // Scenarios: BLTRY-T01, BLTRY-P17, BLTRY-P18
    function test_givenSinglePendingBucket_whenTransferFails_thenRetryPaysExactlyOnce(
        uint8 bucket_,
        address caller_,
        uint128 amount_
    ) public {
        // The bound constrains the value to the uint8 range.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 bucket = uint8(bound(bucket_, 0, 2));
        uint256 amount = bound(amount_, 1, type(uint128).max);
        address recipient = bucket == 2 ? alice : address(trsry);
        IBurnerLoans.PayoutKind kind = bucket == 0 ? IBurnerLoans.PayoutKind.Fee : bucket == 1
            ? IBurnerLoans.PayoutKind.Seizure
            : IBurnerLoans.PayoutKind.SeizureReward;

        MockRevertingTransferToken tokenImplementation = new MockRevertingTransferToken(
            _collateralDecimals()
        );
        vm.etch(address(usds), address(tokenImplementation).code);
        MockRevertingTransferToken liveToken = MockRevertingTransferToken(address(usds));
        liveToken.setTransferReverts(recipient, true);

        if (bucket == 0) {
            liveToken.mint(alice, amount);
            vm.prank(alice);
            liveToken.approve(address(burnerLoans), amount);
            burnerLoans.recordPendingFeeForTest(address(usds), alice, recipient, amount);
        } else {
            liveToken.mint(address(burnerLoans), amount);
            if (bucket == 1) {
                burnerLoans.recordPendingSeizedCollateralForTest(address(usds), recipient, amount);
            } else {
                burnerLoans.recordPendingSeizureRewardForTest(address(usds), recipient, amount);
            }
        }

        assertEq(
            burnerLoans.pendingPayout(address(usds), recipient),
            amount,
            "failed bucket remains owed"
        );
        assertEq(burnerLoans.totalPendingForTest(address(usds)), amount, "reserve is exact");
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutDeferred(address(usds), recipient, kind, amount);
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(usds), recipient),
            0,
            "blocked retry returns zero"
        );
        liveToken.setTransferReverts(recipient, false);
        uint256 recipientBefore = liveToken.balanceOf(recipient);

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(address(usds), recipient, kind, amount);
        vm.prank(caller_);
        uint256 transferred = burnerLoans.transferPendingPayout(address(usds), recipient);

        assertEq(transferred, amount, "retry returns the delivered amount");
        assertEq(liveToken.balanceOf(recipient) - recipientBefore, amount, "recipient paid once");
        assertEq(burnerLoans.pendingPayout(address(usds), recipient), 0, "recipient debt clears");
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "reserve clears");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "token index clears");

        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(usds), recipient),
            0,
            "repeat retry is a no-op"
        );
        assertEq(liveToken.balanceOf(recipient) - recipientBefore, amount, "no double payment");
    }

    // Scenarios: BLTRY-L03
    function test_givenNoPending_whenEnumerated_returnsEmptyArrays() public view {
        assertEq(burnerLoans.pendingPayout(address(usds), alice), 0, "no recipient is owed");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "no pending tokens");
        assertEq(
            burnerLoans.getPendingPayoutRecipients(address(usds)).length,
            0,
            "no pending recipients"
        );
    }

    // Scenarios: BLTRY-C02
    function test_givenPendingFee_whenTokenPropagatesReentrantFailure_thenRetryRemainsPending()
        public
    {
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        vm.stopPrank();
        uint256 fee = burnerLoans.previewBorrow(address(usds), 100e9, alice).fee;
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(trsry)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutDeferred(
            address(usds),
            address(trsry),
            IBurnerLoans.PayoutKind.Fee,
            fee
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), 100e9, alice, alice, fee);
        vm.clearMockedCalls();

        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        vm.etch(address(usds), address(callbackToken).code);
        ReentrantFeeToken liveToken = ReentrantFeeToken(address(usds));
        liveToken.setCallbackFrom(
            address(burnerLoans),
            address(burnerLoans),
            abi.encodeCall(burnerLoans.transferPendingPayout, (address(usds), address(trsry)))
        );
        liveToken.setBubbleCallbackFailure(true);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        uint256 transferred = burnerLoans.transferPendingPayout(address(usds), address(trsry));

        assertEq(transferred, 0, "rejected retry reports no transfer");
        assertEq(usds.balanceOf(address(trsry)), treasuryBefore, "failed retry transfers nothing");
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(trsry)),
            fee,
            "failed retry retains entire fee"
        );
        assertEq(burnerLoans.getPendingPayoutTokens().length, 1, "fee remains discoverable");

        liveToken.setBubbleCallbackFailure(false);
        burnerLoans.transferPendingPayout(address(usds), address(trsry));
        assertFalse(liveToken.callbackSucceeded(), "nested retry remains blocked");
        assertEq(
            liveToken.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "nested retry hits shared guard"
        );
        assertEq(usds.balanceOf(address(trsry)) - treasuryBefore, fee, "fee eventually pays once");
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(trsry)),
            0,
            "eventual payout clears debt"
        );
    }

    function _seedCallbackBuckets(ReentrantFeeToken token_, CallbackCase memory case_) internal {
        vm.mockCallRevert(
            address(token_),
            abi.encodeWithSelector(token_.transfer.selector, address(trsry)),
            abi.encodeWithSignature("Error(string)", "seed pending")
        );
        token_.mint(alice, case_.fee);
        vm.prank(alice);
        token_.approve(address(burnerLoans), case_.fee);
        burnerLoans.recordPendingFeeForTest(address(token_), alice, address(trsry), case_.fee);
        if (case_.bucket >= 1) {
            token_.mint(address(burnerLoans), case_.seizure);
            burnerLoans.recordPendingSeizedCollateralForTest(
                address(token_),
                address(trsry),
                case_.seizure
            );
        }
        if (case_.bucket == 2) {
            token_.mint(address(burnerLoans), case_.reward);
            burnerLoans.recordPendingSeizureRewardForTest(
                address(token_),
                address(trsry),
                case_.reward
            );
        }
        vm.clearMockedCalls();
    }

    function _expectCallbackPayoutEvents(
        ReentrantFeeToken token_,
        CallbackCase memory case_,
        bool bubbleFailure_
    ) internal {
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        if (case_.bucket == 0 && bubbleFailure_) {
            emit IBurnerLoans.PayoutDeferred(
                address(token_),
                address(trsry),
                IBurnerLoans.PayoutKind.Fee,
                case_.fee
            );
        } else {
            emit IBurnerLoans.PayoutTransferred(
                address(token_),
                address(trsry),
                IBurnerLoans.PayoutKind.Fee,
                case_.fee
            );
        }
        if (case_.bucket >= 1) {
            vm.expectEmit(true, true, true, true, address(burnerLoans));
            if (case_.bucket == 1 && bubbleFailure_) {
                emit IBurnerLoans.PayoutDeferred(
                    address(token_),
                    address(trsry),
                    IBurnerLoans.PayoutKind.Seizure,
                    case_.seizure
                );
            } else {
                emit IBurnerLoans.PayoutTransferred(
                    address(token_),
                    address(trsry),
                    IBurnerLoans.PayoutKind.Seizure,
                    case_.seizure
                );
            }
        }
        if (case_.bucket == 2) {
            vm.expectEmit(true, true, true, true, address(burnerLoans));
            if (bubbleFailure_) {
                emit IBurnerLoans.PayoutDeferred(
                    address(token_),
                    address(trsry),
                    IBurnerLoans.PayoutKind.SeizureReward,
                    case_.reward
                );
            } else {
                emit IBurnerLoans.PayoutTransferred(
                    address(token_),
                    address(trsry),
                    IBurnerLoans.PayoutKind.SeizureReward,
                    case_.reward
                );
            }
        }
    }

    function _assertCallbackRetryResult(
        ReentrantFeeToken token_,
        CallbackCase memory case_,
        bool bubbleFailure_,
        uint256 transferred_
    ) internal view {
        if (bubbleFailure_) {
            assertEq(transferred_, case_.leading, "only leading healthy buckets transfer");
            assertEq(
                token_.balanceOf(address(trsry)),
                case_.leading,
                "recipient receives healthy subtotal"
            );
            assertEq(
                burnerLoans.totalPendingForTest(address(token_)),
                case_.target,
                "callback bucket remains reserved"
            );
            assertEq(
                burnerLoans.pendingFeeForTest(address(token_)),
                case_.bucket == 0 ? case_.fee : 0,
                "fee bucket state is exact"
            );
            assertEq(
                burnerLoans.pendingSeizureForTest(address(token_)),
                case_.bucket == 1 ? case_.seizure : 0,
                "seizure bucket state is exact"
            );
            assertEq(
                burnerLoans.pendingSeizureRewardForTest(address(token_), address(trsry)),
                case_.bucket == 2 ? case_.reward : 0,
                "keeper bucket state is exact"
            );
            assertEq(burnerLoans.getPendingPayoutTokens().length, 1, "failed token stays indexed");
            assertEq(
                burnerLoans.getPendingPayoutRecipients(address(token_)).length,
                1,
                "failed recipient stays indexed"
            );
            return;
        }

        assertFalse(token_.callbackSucceeded(), "nested guarded call is rejected");
        assertEq(
            token_.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "nested call reaches shared guard"
        );
        assertEq(transferred_, case_.leading + case_.target, "all buckets transfer exactly once");
        assertEq(
            token_.balanceOf(address(trsry)),
            case_.leading + case_.target,
            "recipient receives exact total"
        );
        assertEq(burnerLoans.totalPendingForTest(address(token_)), 0, "all callback debt clears");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "token index clears");
        assertEq(
            burnerLoans.getPendingPayoutRecipients(address(token_)).length,
            0,
            "recipient index clears"
        );
    }

    // Scenarios: BLTRY-C01, BLTRY-C02
    function test_givenPayoutTokenCallback_retryHandlesEveryBucket(
        uint8 bucketSeed_,
        bool bubbleFailure_,
        bool nestedRetry_,
        address caller_
    ) public {
        // The bound constrains the value to the uint8 range.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 bucket = uint8(bound(bucketSeed_, 0, 2));
        CallbackCase memory callbackCase = CallbackCase({
            bucket: bucket,
            fee: 3,
            seizure: 5,
            reward: 7,
            leading: bucket == 0 ? 0 : bucket == 1 ? 3 : 8,
            target: bucket == 0 ? 3 : bucket == 1 ? 5 : 7
        });
        ReentrantFeeToken token = new ReentrantFeeToken();
        _seedCallbackBuckets(token, callbackCase);
        bytes memory callbackData = nestedRetry_
            ? abi.encodeCall(burnerLoans.transferPendingPayout, (address(token), address(trsry)))
            : abi.encodeCall(burnerLoans.claimYield, (address(usds)));
        token.setCallbackFrom(address(burnerLoans), address(burnerLoans), callbackData);
        token.setCallbackPhases(true, false);
        token.setCallbackTransferRecipient(address(trsry));
        token.setCallbackOnTransferCall(uint256(bucket) + 1);
        token.setBubbleCallbackFailure(bubbleFailure_);

        _expectCallbackPayoutEvents(token, callbackCase, bubbleFailure_);
        vm.prank(caller_);
        uint256 transferred = burnerLoans.transferPendingPayout(address(token), address(trsry));
        _assertCallbackRetryResult(token, callbackCase, bubbleFailure_, transferred);
    }

    // Scenarios: BLTRY-C01
    function test_givenPendingFee_whenTokenReentersRetry_thenNestedCallFailsAndFeePaysOnce()
        public
    {
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        vm.stopPrank();
        uint256 fee = burnerLoans.previewBorrow(address(usds), 100e9, alice).fee;
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(trsry)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), 100e9, alice, alice, fee);
        vm.clearMockedCalls();
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(trsry)),
            fee,
            "fee remains pending"
        );

        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        vm.etch(address(usds), address(callbackToken).code);
        ReentrantFeeToken(address(usds)).setCallbackFrom(
            address(burnerLoans),
            address(burnerLoans),
            abi.encodeCall(burnerLoans.transferPendingPayout, (address(usds), address(trsry)))
        );
        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        burnerLoans.transferPendingPayout(address(usds), address(trsry));

        assertFalse(ReentrantFeeToken(address(usds)).callbackSucceeded(), "nested retry fails");
        assertEq(
            ReentrantFeeToken(address(usds)).callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "nested retry hits shared guard"
        );
        assertEq(usds.balanceOf(address(trsry)) - treasuryBefore, fee, "fee pays once");
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(trsry)),
            0,
            "pending fee clears once"
        );
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "pending set clears once");
    }

    // Scenarios: BLTRY-P02, BLTRY-P09
    function test_givenFeePendingToOldTreasury_whenInactiveAndTreasuryUpgraded_retryBeforeReactivation_reverts()
        public
    {
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        vm.stopPrank();
        uint256 fee = burnerLoans.previewBorrow(address(usds), 100e9, alice).fee;
        uint256 formerTreasuryBefore = usds.balanceOf(address(trsry));
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(trsry)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), 100e9, alice, alice, fee);
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(trsry)),
            fee,
            "fee remains pending by token"
        );
        address[] memory tokens = burnerLoans.getPendingPayoutTokens();
        assertEq(tokens.length, 1, "one pending token is discoverable");
        assertEq(tokens[0], address(usds), "pending token is USDS");
        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(usds));
        assertEq(recipients.length, 1, "one fee destination is discoverable");
        assertEq(recipients[0], address(trsry), "current Treasury is the fee recipient");
        vm.clearMockedCalls();

        _deactivatePolicy(address(burnerLoans));
        vm.prank(admin);
        OlympusTreasury newTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));
        vm.expectRevert(IBurnerLoans.BurnerLoans_PolicyInactive.selector);
        burnerLoans.transferPendingPayout(address(usds), address(trsry));
        assertEq(usds.balanceOf(address(newTreasury)), 0, "inactive facility transfers nothing");
        _activatePolicy(address(burnerLoans));
        recipients = burnerLoans.getPendingPayoutRecipients(address(usds));
        assertEq(recipients[0], address(newTreasury), "reactivation refreshes Treasury");
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(usds),
            address(newTreasury),
            IBurnerLoans.PayoutKind.Fee,
            fee
        );
        uint256 transferred = burnerLoans.transferPendingPayout(
            address(usds),
            address(newTreasury)
        );
        assertEq(transferred, fee, "retry returns the delivered fee amount");

        assertEq(
            usds.balanceOf(address(trsry)),
            formerTreasuryBefore,
            "former Treasury receives no pending fee"
        );
        assertEq(usds.balanceOf(address(newTreasury)), fee, "new Treasury receives pending fee");
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(newTreasury)),
            0,
            "pending fee clears"
        );
    }

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _assertSinglePendingReward(uint256 amount_) internal view {
        assertEq(
            burnerLoans.pendingPayout(address(usds), alice),
            amount_,
            "pending getter remains exact"
        );
        address[] memory tokens = burnerLoans.getPendingPayoutTokens();
        assertEq(tokens.length, 1, "one pending token remains readable");
        assertEq(tokens[0], address(usds), "pending token remains exact");
        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(usds));
        assertEq(recipients.length, 1, "one pending recipient remains readable");
        assertEq(recipients[0], alice, "pending recipient remains exact");
        assertEq(
            burnerLoans.totalPendingForTest(address(usds)),
            amount_,
            "aggregate reserve remains exact"
        );
    }

    // Scenarios: BLTRY-L01
    function test_givenDisabled_whenAnyCallerRetries_reverts(address caller_) public {
        _disableBurnerLoans(admin);

        vm.prank(caller_);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.transferPendingPayout(address(usds), alice);

        assertEq(burnerLoans.pendingPayout(address(usds), alice), 0, "no payout is created");
    }

    // Condition tree:
    // - Payout state: no amount owed for arbitrary token and recipient
    // - Policy state: disabled and Kernel-inactive
    // - Caller: arbitrary address; retry is rejected before any transfer
    function testFuzz_givenNoPending_givenInactive_whenAnyCallerFlushes_reverts(
        address caller_,
        address recipient_
    ) public {
        _disableBurnerLoans(admin);
        _deactivatePolicy(address(burnerLoans));

        vm.prank(caller_);
        vm.expectRevert(IBurnerLoans.BurnerLoans_PolicyInactive.selector);
        burnerLoans.transferPendingPayout(address(usds), recipient_);

        assertEq(burnerLoans.pendingPayout(address(usds), recipient_), 0, "no payout is created");
    }

    // Condition tree:
    // - Payout state: positive fee owed to a distributor that rejected transfer
    // - Policy state: disabled and Kernel-inactive after the borrow
    // - Caller: unrelated address retries after reactivation and re-enablement
    function test_givenPendingFee_givenInactive_whenUnrelatedCallerFlushesAfterReactivation()
        public
    {
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        vm.stopPrank();
        RevenueDistributor distributor = _installFeeDistributorForTest(address(usds));
        uint256 fee = burnerLoans.previewBorrow(address(usds), 100e9, alice).fee;
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(distributor)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), 100e9, alice, alice, fee);
        vm.prank(makeAddr("earlyRetry"));
        burnerLoans.transferPendingPayout(address(usds), address(distributor));
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(distributor)),
            fee,
            "blocked retry retains the payout"
        );
        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(usds));
        assertEq(recipients.length, 1, "pending fee has one current destination");
        assertEq(recipients[0], address(distributor), "current distributor is discoverable");
        vm.clearMockedCalls();
        _disableBurnerLoans(admin);
        _deactivatePolicy(address(burnerLoans));

        vm.prank(makeAddr("unrelated"));
        vm.expectRevert(IBurnerLoans.BurnerLoans_PolicyInactive.selector);
        burnerLoans.transferPendingPayout(address(usds), address(distributor));
        assertEq(usds.balanceOf(address(distributor)), 0, "inactive facility sends no fee");
        _activatePolicy(address(burnerLoans));
        vm.prank(makeAddr("disabledRetry"));
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.transferPendingPayout(address(usds), address(distributor));
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(distributor)),
            fee,
            "disabled facility retains the fee"
        );
        vm.prank(admin);
        burnerLoans.reEnable();
        vm.prank(makeAddr("unrelated"));
        burnerLoans.transferPendingPayout(address(usds), address(distributor));

        assertEq(usds.balanceOf(address(distributor)), fee, "pending fee is delivered");
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(distributor)),
            0,
            "payout is cleared"
        );
    }

    // Scenarios: BLTRY-P02, BLTRY-P05
    function test_givenPendingFee_whenDistributorChanges_thenRetryPaysNewDistributor() public {
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        vm.stopPrank();
        RevenueDistributor former = _installFeeDistributorForTest(address(usds));
        uint256 fee = burnerLoans.previewBorrow(address(usds), 100e9, alice).fee;
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(former)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), 100e9, alice, alice, fee);
        vm.clearMockedCalls();

        RevenueDistributor current = _installRevenueDistributorForTest(address(usds));
        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(usds));
        assertEq(recipients.length, 1, "one fee recipient remains");
        assertEq(recipients[0], address(current), "recipient list follows new distributor");
        burnerLoans.transferPendingPayout(address(usds), address(former));
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(current)),
            fee,
            "former distributor cannot claim fee"
        );
        vm.startSnapshotGas("BurnerLoans.transferPendingPayout.feeToReplacementDistributor");
        burnerLoans.transferPendingPayout(address(usds), address(current));
        uint256 retryGas = vm.stopSnapshotGas();

        assertGt(retryGas, 0, "replacement distributor retry gas is recorded");

        assertEq(usds.balanceOf(address(former)), 0, "former distributor receives nothing");
        assertEq(usds.balanceOf(address(current)), fee, "new distributor receives old fee");
        assertEq(burnerLoans.pendingPayout(address(usds), address(current)), 0, "fee clears once");
    }

    // given the distributor is selected and its token transfer reverts
    //   given a fee remains pending
    //     when sendFeesToDistributor changes to false and Treasury is retried
    //       [X] only Treasury receives the old fee
    // Scenarios: BLTRY-P02, BLTRY-P07
    function test_givenPendingFeeToDistributor_whenFeeFlagChanges_paysTreasury() public {
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        vm.stopPrank();
        RevenueDistributor former = _installFeeDistributorForTest(address(usds));
        uint256 fee = burnerLoans.previewBorrow(address(usds), 100e9, alice).fee;
        MockRevertingTransferToken tokenImplementation = new MockRevertingTransferToken(
            _collateralDecimals()
        );
        vm.etch(address(usds), address(tokenImplementation).code);
        MockRevertingTransferToken(address(usds)).setTransferReverts(address(former), true);
        vm.prank(alice);
        burnerLoans.borrow(address(usds), 100e9, alice, alice, fee);
        MockRevertingTransferToken(address(usds)).setTransferReverts(address(former), false);
        _setSendFeesToDistributor(false);

        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        uint256 transferred = burnerLoans.transferPendingPayout(address(usds), address(trsry));

        assertEq(transferred, fee, "retry returns the transferred fee");
        assertEq(
            usds.balanceOf(address(trsry)) - treasuryBefore,
            fee,
            "current Treasury receives fee"
        );
        assertEq(usds.balanceOf(address(former)), 0, "former destination receives nothing");
        assertEq(burnerLoans.pendingPayout(address(usds), address(trsry)), 0, "fee is cleared");
    }

    // Scenarios: BLTRY-P08
    function test_givenTreasuryFeePending_whenDistributorRoutingEnabled_feeFollowsDistributor(
        address caller_
    ) public {
        uint256 fee = 11;
        usds.mint(alice, fee);
        vm.prank(alice);
        usds.approve(address(burnerLoans), fee);
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(trsry)),
            abi.encodeWithSignature("Error(string)", "blocked")
        );
        burnerLoans.recordPendingFeeForTest(address(usds), alice, address(trsry), fee);
        vm.clearMockedCalls();
        RevenueDistributor distributor = _installFeeDistributorForTest(address(usds));

        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(usds), address(trsry)),
            0,
            "former Treasury has no fee entitlement"
        );
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(usds),
            address(distributor),
            IBurnerLoans.PayoutKind.Fee,
            fee
        );
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(usds), address(distributor)),
            fee,
            "current distributor receives the fee"
        );
        assertEq(usds.balanceOf(address(distributor)), fee, "distributor balance is exact");
        assertEq(usds.balanceOf(address(trsry)), 0, "Treasury receives no redirected fee");
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "fee reserve clears");
    }

    // Scenarios: BLTRY-P05, BLTRY-P07
    function test_givenFeeRouteChanges_retryUsesOnlyCurrentRecipient(
        bool replaceDistributor_,
        address caller_,
        uint128 amountSeed_
    ) public {
        uint256 amount = bound(amountSeed_, 1, type(uint128).max);
        MockRevertingTransferToken token = new MockRevertingTransferToken(_collateralDecimals());
        RevenueDistributor former = _installFeeDistributorForTest(address(token));
        token.setTransferReverts(address(former), true);
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(burnerLoans), amount);
        burnerLoans.recordPendingFeeForTest(address(token), alice, address(former), amount);
        token.setTransferReverts(address(former), false);

        address current;
        if (replaceDistributor_) {
            current = address(_installRevenueDistributorForTest(address(token)));
        } else {
            _setSendFeesToDistributor(false);
            current = address(trsry);
        }
        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(token), address(former)),
            0,
            "former fee route has no entitlement"
        );
        assertEq(vm.getRecordedLogs().length, 0, "former route emits no payout event");
        assertEq(token.balanceOf(address(former)), 0, "former route receives nothing");
        assertEq(burnerLoans.pendingFeeForTest(address(token)), amount, "fee debt follows role");
        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(token));
        assertEq(recipients.length, 1, "one current recipient is indexed");
        assertEq(recipients[0], current, "recipient index follows current route");

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(token),
            current,
            IBurnerLoans.PayoutKind.Fee,
            amount
        );
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(token), current),
            amount,
            "current route receives exact fee"
        );
        assertEq(token.balanceOf(current), amount, "current route balance is exact");
        assertEq(burnerLoans.pendingFeeForTest(address(token)), 0, "fee debt clears");
        assertEq(burnerLoans.totalPendingForTest(address(token)), 0, "reserve clears");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "token index clears");
        assertEq(
            burnerLoans.getPendingPayoutRecipients(address(token)).length,
            0,
            "recipient index clears"
        );
    }

    // Scenarios: BLTRY-P08
    function test_givenTreasuryFeeRouteMovesToDistributor_otherBucketsStayBound(
        bool includeSeizure_,
        bool includeKeeper_,
        address caller_
    ) public {
        uint256 fee = 11;
        uint256 seizure = includeSeizure_ ? 13 : 0;
        uint256 reward = includeKeeper_ ? 17 : 0;
        MockRevertingTransferToken token = new MockRevertingTransferToken(_collateralDecimals());
        address fixedKeeper = makeAddr("fixed keeper");
        token.setTransferReverts(address(trsry), true);
        token.setTransferReverts(fixedKeeper, true);
        token.mint(alice, fee);
        vm.prank(alice);
        token.approve(address(burnerLoans), fee);
        burnerLoans.recordPendingFeeForTest(address(token), alice, address(trsry), fee);
        if (seizure != 0) {
            token.mint(address(burnerLoans), seizure);
            burnerLoans.recordPendingSeizedCollateralForTest(
                address(token),
                address(trsry),
                seizure
            );
        }
        if (reward != 0) {
            token.mint(address(burnerLoans), reward);
            burnerLoans.recordPendingSeizureRewardForTest(address(token), fixedKeeper, reward);
        }
        token.setTransferReverts(address(trsry), false);
        token.setTransferReverts(fixedKeeper, false);
        RevenueDistributor distributor = _installFeeDistributorForTest(address(token));

        if (seizure != 0) {
            vm.expectEmit(true, true, true, true, address(burnerLoans));
            emit IBurnerLoans.PayoutTransferred(
                address(token),
                address(trsry),
                IBurnerLoans.PayoutKind.Seizure,
                seizure
            );
        }
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(token), address(trsry)),
            seizure,
            "former fee route receives only its live seizure debt"
        );
        assertEq(token.balanceOf(address(trsry)), seizure, "Treasury receives only seizure debt");
        assertEq(burnerLoans.pendingFeeForTest(address(token)), fee, "fee follows distributor");
        assertEq(
            burnerLoans.pendingSeizureRewardForTest(address(token), fixedKeeper),
            reward,
            "fixed keeper debt is preserved"
        );

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(token),
            address(distributor),
            IBurnerLoans.PayoutKind.Fee,
            fee
        );
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(token), address(distributor)),
            fee,
            "distributor receives exact fee"
        );
        assertEq(token.balanceOf(address(distributor)), fee, "distributor balance is exact");
        assertEq(burnerLoans.pendingFeeForTest(address(token)), 0, "fee clears");
        assertEq(
            burnerLoans.totalPendingForTest(address(token)),
            reward,
            "only optional fixed reward remains"
        );
        address[] memory recipients = burnerLoans.getPendingPayoutRecipients(address(token));
        assertEq(recipients.length, reward == 0 ? 0 : 1, "recipient index is exact");
        if (reward != 0) assertEq(recipients[0], fixedKeeper, "fixed keeper remains indexed");
    }

    // Scenarios: BLTRY-P09
    function test_givenTreasuryUpgrades_combinedRoleDebtFollowsCurrentTreasury(
        address caller_
    ) public {
        uint256 fee = 23;
        uint256 seizure = 29;
        uint256 reward = 31;
        uint256 unrelatedFee = 37;
        MockRevertingTransferToken token = new MockRevertingTransferToken(_collateralDecimals());
        MockRevertingTransferToken otherToken = new MockRevertingTransferToken(
            _collateralDecimals()
        );
        address formerTreasury = address(trsry);
        address fixedKeeper = makeAddr("upgrade fixed keeper");
        token.setTransferReverts(formerTreasury, true);
        token.setTransferReverts(fixedKeeper, true);
        token.mint(alice, fee);
        vm.prank(alice);
        token.approve(address(burnerLoans), fee);
        burnerLoans.recordPendingFeeForTest(address(token), alice, formerTreasury, fee);
        token.mint(address(burnerLoans), seizure + reward);
        burnerLoans.recordPendingSeizedCollateralForTest(address(token), formerTreasury, seizure);
        burnerLoans.recordPendingSeizureRewardForTest(address(token), fixedKeeper, reward);
        otherToken.setTransferReverts(formerTreasury, true);
        otherToken.mint(alice, unrelatedFee);
        vm.prank(alice);
        otherToken.approve(address(burnerLoans), unrelatedFee);
        burnerLoans.recordPendingFeeForTest(
            address(otherToken),
            alice,
            formerTreasury,
            unrelatedFee
        );
        token.setTransferReverts(formerTreasury, false);
        token.setTransferReverts(fixedKeeper, false);
        otherToken.setTransferReverts(formerTreasury, false);

        _deactivatePolicy(address(burnerLoans));
        OlympusTreasury currentTreasury = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(currentTreasury));
        _activatePolicy(address(burnerLoans));

        vm.recordLogs();
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(token), formerTreasury),
            0,
            "former Treasury has no role debt"
        );
        assertEq(vm.getRecordedLogs().length, 0, "former Treasury emits no payout event");
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(token),
            address(currentTreasury),
            IBurnerLoans.PayoutKind.Fee,
            fee
        );
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(token),
            address(currentTreasury),
            IBurnerLoans.PayoutKind.Seizure,
            seizure
        );
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(token), address(currentTreasury)),
            fee + seizure,
            "current Treasury receives both role buckets"
        );

        assertEq(token.balanceOf(formerTreasury), 0, "former Treasury receives nothing");
        assertEq(
            token.balanceOf(address(currentTreasury)),
            fee + seizure,
            "current Treasury balance is exact"
        );
        assertEq(burnerLoans.pendingFeeForTest(address(token)), 0, "role fee clears");
        assertEq(burnerLoans.pendingSeizureForTest(address(token)), 0, "role seizure clears");
        assertEq(
            burnerLoans.pendingSeizureRewardForTest(address(token), fixedKeeper),
            reward,
            "fixed reward is preserved"
        );
        assertEq(
            burnerLoans.pendingFeeForTest(address(otherToken)),
            unrelatedFee,
            "unrelated token fee is preserved"
        );
        assertEq(
            burnerLoans.totalPendingForTest(address(token)),
            reward,
            "only fixed reward remains for role token"
        );
        assertEq(
            burnerLoans.totalPendingForTest(address(otherToken)),
            unrelatedFee,
            "unrelated token reserve is preserved"
        );
    }

    // Scenarios: BLTRY-P10
    function test_givenFormerDistributorIsKeeper_rotationPreservesOnlyFixedReward(
        address caller_
    ) public {
        uint256 fee = 13;
        uint256 reward = 17;
        RevenueDistributor former = _installFeeDistributorForTest(address(usds));
        usds.mint(alice, fee);
        vm.prank(alice);
        usds.approve(address(burnerLoans), fee);
        usds.mint(address(burnerLoans), reward);
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(former)),
            abi.encodeWithSignature("Error(string)", "blocked")
        );
        burnerLoans.recordPendingFeeForTest(address(usds), alice, address(former), fee);
        burnerLoans.recordPendingSeizureRewardForTest(address(usds), address(former), reward);
        vm.clearMockedCalls();

        RevenueDistributor current = _installRevenueDistributorForTest(address(usds));
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(usds),
            address(former),
            IBurnerLoans.PayoutKind.SeizureReward,
            reward
        );
        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(usds), address(former)),
            reward,
            "former role receives only its fixed reward"
        );
        assertEq(usds.balanceOf(address(former)), reward, "former distributor reward is exact");
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(current)),
            fee,
            "fee follows the current distributor"
        );

        vm.prank(caller_);
        assertEq(
            burnerLoans.transferPendingPayout(address(usds), address(current)),
            fee,
            "current distributor receives only the fee"
        );
        assertEq(usds.balanceOf(address(current)), fee, "current distributor fee is exact");
        assertEq(burnerLoans.totalPendingForTest(address(usds)), 0, "all buckets clear");
    }

    // Scenarios: BOR-P03
    function test_givenTransferNeedsMoreThanFormerCap_whenBorrowed_thenFeePaysImmediately(
        bool sendFeesToDistributor_
    ) public {
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        vm.stopPrank();
        address recipient = _configureFeeRecipientForTest(sendFeesToDistributor_, address(usds));
        GasSensitivePayoutToken gasToken = new GasSensitivePayoutToken();
        vm.etch(address(usds), address(gasToken).code);
        GasSensitivePayoutToken(address(usds)).setNeedsMoreGas(true);
        uint256 fee = burnerLoans.previewBorrow(address(usds), 100e9, alice).fee;
        uint256 recipientBefore = usds.balanceOf(recipient);
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.PayoutTransferred(
            address(usds),
            recipient,
            IBurnerLoans.PayoutKind.Fee,
            fee
        );

        vm.prank(alice);
        burnerLoans.borrow(address(usds), 100e9, alice, alice, fee);
        assertEq(usds.balanceOf(recipient) - recipientBefore, fee, "fee pays without transfer cap");
        assertEq(burnerLoans.pendingPayout(address(usds), recipient), 0, "fee debt is cleared");
        assertEq(burnerLoans.getPendingPayoutTokens().length, 0, "no payout is left pending");
    }

    function test_givenPendingFee_whenHeartRuns_thenFeeRemainsForDirectRetry() public {
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        vm.stopPrank();
        RevenueDistributor distributor = _installFeeDistributorForTest(address(usds));
        uint256 fee = burnerLoans.previewBorrow(address(usds), 100e9, alice).fee;
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(distributor)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), 100e9, alice, alice, fee);
        vm.clearMockedCalls();

        address heart = makeAddr("heart");
        vm.startPrank(admin);
        BurnerLoansYieldClaimer claimer = new BurnerLoansYieldClaimer(
            kernel,
            address(burnerLoans),
            2_000_000
        );
        kernel.executeAction(Actions.ActivatePolicy, address(claimer));
        rolesAdmin.grantRole(HEART_ROLE, heart);
        claimer.enable("");
        vm.stopPrank();
        vm.prank(heart);
        claimer.execute();

        assertEq(usds.balanceOf(address(distributor)), 0, "Heart task does not retry the fee");
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(distributor)),
            fee,
            "fee remains available for retry"
        );
        burnerLoans.transferPendingPayout(address(usds), address(distributor));
        assertEq(usds.balanceOf(address(distributor)), fee, "direct retry delivers the fee");
    }
}

// forge-lint: disable-end(unused-return,literal-instead-of-constant)
