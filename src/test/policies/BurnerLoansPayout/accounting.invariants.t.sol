// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Finite seed and invariant loops intentionally call real contracts.
// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

// Interfaces
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {PayoutAccountingHandler} from "./fixtures/PayoutAccountingHandler.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";

contract BurnerLoansPayoutAccountingInvariantsTest is BurnerLoansPayoutTest {
    struct RecipientTotals {
        uint256 keepers;
        uint256 referrers;
        uint256 recipients;
        uint256 paid;
    }

    PayoutAccountingHandler internal _handler;

    function setUp() public override {
        super.setUp();
        _bindDistributor();
        _handler = new PayoutAccountingHandler(
            _subject,
            address(_core),
            [_token, _otherToken],
            [_treasury(), address(_distributor), _keeper],
            _destination,
            IBurnerLoansRisk(address(_risk)),
            address(_otherPayout)
        );
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_handler));
        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = _handler.creditFee.selector;
        selectors[1] = _handler.creditSeizure.selector;
        selectors[2] = _handler.retry.selector;
        selectors[3] = _handler.setBlocked.selector;
        selectors[4] = _handler.setFeeRoute.selector;
        selectors[5] = _handler.setEnabled.selector;
        selectors[6] = _handler.rescueSurplus.selector;
        selectors[7] = _handler.rescuePending.selector;
        selectors[8] = _handler.creditReferral.selector;
        selectors[9] = _handler.setSelected.selector;
        selectors[10] = _handler.setReferralShare.selector;
        selectors[11] = _handler.setReferrer.selector;
        selectors[12] = _handler.donate.selector;
        selectors[13] = _handler.setGracePeriod.selector;
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
        targetContract(address(_handler));
    }

    // Scenarios: BLCUTRY-P21.
    function test_givenReferralOnly_whenModelRescuesBoundarySeeds() public {
        _handler.setBlocked(0, 2, true);
        _handler.creditReferral(0, 2, 0, 25);
        _handler.rescuePending(0, 2, 1);
        invariant_backingBucketsIndexesAndRoutes();
        _handler.rescuePending(0, 2, 24);
        invariant_backingBucketsIndexesAndRoutes();
        assertEq(
            _handler.referralRescued(0, 2),
            25,
            "Model attributes all redirected referral units"
        );
    }

    // Scenarios: BLCUTRY-P21, BLCU-REENABLE-V01.
    function invariant_backingBucketsIndexesAndRoutes() public view {
        assertEq(
            _payout.lastTransitionAt(),
            _handler.lastTransitionAt(),
            "Only explicit transitions update history"
        );
        assertEq(
            _payout.gracePeriod(),
            _handler.gracePeriod(),
            "Only authorized enabled configuration changes grace"
        );
        assertEq(
            _core.payout(),
            _handler.selected() ? address(_payout) : address(_otherPayout),
            "Selected Payout follows independent model"
        );
        assertEq(
            _risk.referralFeeBps(),
            _handler.referralBps(),
            "Risk share changes do not reprice earned rewards"
        );
        assertEq(
            _payout.isEnabled(),
            _handler.enabled(),
            "Only explicit local transitions change admission"
        );
        assertEq(
            _payout.sendFeesToDistributor(),
            _handler.feeRoute() == 1,
            "Routing follows independent model"
        );
        uint256 indexedTokens;
        for (uint256 t; t < 2; ++t)
            indexedTokens += _assertTokenAccounting(t, t == 0 ? _token : _otherToken);
        assertEq(
            _payout.getPendingPayoutTokens().length,
            indexedTokens,
            "Token index has no stale entries"
        );
    }

    function _assertTokenAccounting(
        uint256 t_,
        MockRevertingTransferToken token_
    ) internal view returns (uint256) {
        (
            uint256 fee,
            uint256 referral,
            uint256 seized,
            uint256 keeperReward,
            uint256 total
        ) = _payout.pendingAmounts(address(token_));
        assertEq(fee, _handler.fee(t_), "Raw fee matches model");
        assertEq(seized, _handler.seized(t_), "Raw seizure matches model");
        assertEq(
            referral,
            _handler.referral(t_, 0) + _handler.referral(t_, 1) + _handler.referral(t_, 2),
            "Aggregate referral reserve matches independent per-recipient model"
        );
        assertEq(
            keeperReward,
            _handler.reward(t_, 0) + _handler.reward(t_, 1) + _handler.reward(t_, 2),
            "Aggregate keeper reserve matches independent per-recipient model"
        );
        assertEq(total, fee + referral + seized + keeperReward, "Complete breakdown sums to total");
        assertEq(total, _handler.total(t_), "Aggregate equals independent bucket sum");
        assertEq(
            token_.balanceOf(address(_payout)),
            total + _handler.surplus(t_),
            "Custody exactly backs obligations plus independently donated surplus"
        );
        assertGe(token_.balanceOf(address(_payout)), total, "Every pending unit remains backed");
        assertEq(
            _subject.hasPendingToken(address(token_)),
            total != 0,
            "Stored token membership matches obligations"
        );
        RecipientTotals memory aggregate;
        address[3] memory recipients = [_treasury(), address(_distributor), _keeper];
        for (uint256 k; k < recipients.length; ++k) {
            RecipientTotals memory individual = _assertRecipientAccounting(
                t_,
                token_,
                k,
                recipients[k]
            );
            aggregate.keepers += individual.keepers;
            aggregate.referrers += individual.referrers;
            aggregate.recipients += individual.recipients;
            aggregate.paid += individual.paid;
        }
        assertEq(
            _payout.getPendingKeepers(address(token_)).length,
            aggregate.keepers,
            "Keeper index has no stale entries"
        );
        assertEq(
            _payout.getPendingReferralRecipients(address(token_)).length,
            aggregate.referrers,
            "Referral recipient index has no stale entries"
        );
        assertEq(
            _payout.getPendingPayoutRecipients(address(token_)).length,
            aggregate.recipients,
            "Recipient index deduplicates overlapping roles"
        );
        assertEq(
            token_.balanceOf(_destination),
            _handler.paid(t_, 3),
            "Recovery destination gets exactly redirected amounts"
        );
        assertEq(
            token_.totalSupply(),
            total + aggregate.paid + _handler.paid(t_, 3) + _handler.surplus(t_),
            "Every minted unit is either backing or delivered"
        );
        return total == 0 ? 0 : 1;
    }

    function _assertRecipientAccounting(
        uint256 t_,
        MockRevertingTransferToken token_,
        uint256 k_,
        address recipient_
    ) internal view returns (RecipientTotals memory result) {
        uint256 reward = _handler.reward(t_, k_);
        assertEq(
            _payout.pendingKeeperReward(address(token_), recipient_),
            reward,
            "Public keeper claim matches independent model"
        );
        assertEq(
            _subject.keeperReward(address(token_), recipient_),
            reward,
            "Raw keeper claim follows original owner"
        );
        assertEq(
            _subject.hasPendingKeeper(address(token_), recipient_),
            reward != 0,
            "Stored keeper membership exact"
        );
        result.keepers = reward == 0 ? 0 : 1;
        uint256 referral = _handler.referral(t_, k_);
        assertEq(
            _risk.isReferrerAllowed(recipient_),
            _handler.allowed(k_),
            "Whitelist changes do not reassign funded rewards"
        );
        assertEq(
            _payout.pendingReferralFee(address(token_), recipient_),
            referral,
            "Raw referral matches fixed-owner model"
        );
        assertEq(
            _subject.hasPendingReferrer(address(token_), recipient_),
            referral != 0,
            "Stored referral index exact"
        );
        assertEq(
            _handler.referralEarned(t_, k_),
            referral + _handler.referralPaid(t_, k_) + _handler.referralRescued(t_, k_),
            "Every earned referral remains paid, pending or explicitly rescued"
        );
        result.referrers = referral == 0 ? 0 : 1;
        uint256 available = _handler.entitlement(t_, k_);
        assertEq(
            _payout.pendingRecipientAmount(address(token_), recipient_),
            available,
            "Read-back agrees with model and current routing"
        );
        result.recipients = available == 0 ? 0 : 1;
        result.paid = _handler.paid(t_, k_);
        assertEq(
            token_.balanceOf(recipient_),
            result.paid,
            "Each recipient receives exactly its modelled deliveries"
        );
    }

    // Scenarios: BLCUTRY-P21.
    function test_givenReferralOnlyAndMixedBuckets_whenModelBoundarySeeds() public {
        _handler.setBlocked(0, 2, true);
        _handler.creditReferral(0, 2, 0, 1);
        invariant_backingBucketsIndexesAndRoutes();
        _handler.donate(0, 1);
        invariant_backingBucketsIndexesAndRoutes();
        _handler.setBlocked(0, 0, true);
        _handler.creditFee(0, 1);
        _handler.creditSeizure(0, 2, 1, 1);
        _handler.setBlocked(1, 1, true);
        _handler.creditReferral(1, 1, 0, 1);
        _handler.donate(1, 1);
        invariant_backingBucketsIndexesAndRoutes();
        _handler.setReferralShare(10_000);
        _handler.setReferrer(2, true);
        _handler.setReferrer(2, false);
        _handler.setSelected(false);
        _handler.retry(0, 2);
        _handler.setBlocked(0, 2, false);
        _handler.retry(0, 2);
        _handler.setEnabled(false);
        _handler.setBlocked(0, 0, false);
        _handler.retry(0, 0);
        invariant_backingBucketsIndexesAndRoutes();
        _handler.setEnabled(true);
        _handler.setSelected(true);
        _handler.rescueSurplus(0, 0);
        invariant_backingBucketsIndexesAndRoutes();
    }

    // Scenarios: BLCUTRY-P21.
    function test_givenMaximumReferralOnly_whenModelBoundarySeed() public {
        _handler.seedMaximumReferral();
        invariant_backingBucketsIndexesAndRoutes();
        _handler.creditSeizure(0, 0, 0, 0);
        _handler.rescueSurplus(0, 0);
        invariant_backingBucketsIndexesAndRoutes();
        _handler.setBlocked(0, 2, false);
        _handler.retry(0, 2);
        invariant_backingBucketsIndexesAndRoutes();
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant)
