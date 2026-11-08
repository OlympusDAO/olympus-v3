// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// Tests read state after calls to assert exact effects and rollback.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth)

// Foundry assertTrue checks both nonzero constructor addresses before storage; the linter
// does not recognize that test assertion as a zero check.
// forge-lint: disable-start(missing-zero-check)

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansPayoutHarness} from "./BurnerLoansPayoutHarness.sol";
import {Test} from "forge-std/Test.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";

/// @dev Two tokens, overlapping recipients, optional failures, governance drift, surplus and local pauses.
///      Unit tests separately cover maxima, authorization, Kernel migration and callbacks.
contract PayoutAccountingHandler is Test {
    BurnerLoansPayoutHarness internal immutable _PAYOUT;
    address internal immutable _CORE;
    address internal immutable _DESTINATION;
    IBurnerLoansRisk internal immutable _RISK;
    address internal immutable _REPLACEMENT;
    MockRevertingTransferToken[2] internal _tokens;
    address[3] internal _recipients;

    uint256[2] public fee;
    uint256[2] public seized;
    uint256[3][2] public reward;
    uint256[3][2] public referral;
    uint256[3][2] public referralEarned;
    uint256[3][2] public referralPaid;
    uint256[3][2] public referralRescued;
    uint256[4][2] public paid;
    uint256[2] public surplus;
    bool[3][2] public blocked;
    uint256 public feeRoute;
    bool public enabled = true;
    bool public selected = true;
    uint16 public referralBps;
    bool[3] public allowed;

    constructor(
        BurnerLoansPayoutHarness payout_,
        address core_,
        MockRevertingTransferToken[2] memory tokens_,
        address[3] memory recipients_,
        address destination_,
        IBurnerLoansRisk risk_,
        address replacement_
    ) {
        assertTrue(core_ != address(0), "Handler requires a real Core");
        assertTrue(destination_ != address(0), "Handler requires a recovery destination");
        _PAYOUT = payout_;
        _CORE = core_;
        _tokens = tokens_;
        _recipients = recipients_;
        _DESTINATION = destination_;
        _RISK = risk_;
        _REPLACEMENT = replacement_;
    }

    function creditFee(uint8 token_, uint80 amount_) external {
        uint256 t = bound(token_, 0, 1);
        uint256 amount = bound(amount_, 0, 1e6);
        if (!enabled || !selected) return;
        _tokens[t].mint(address(_PAYOUT), amount);
        fee[t] += amount;
        if (amount != 0) _payFee(t);
        vm.prank(_CORE);
        _PAYOUT.creditFee(address(_tokens[t]), amount, address(0), 0);
    }

    function creditSeizure(uint8 token_, uint8 keeper_, uint80 reward_, uint80 seized_) external {
        if (!enabled || !selected) return;
        uint256 t = bound(token_, 0, 1);
        uint256 k = bound(keeper_, 0, 2);
        uint256 r = bound(reward_, 0, 1e6);
        uint256 s = bound(seized_, 0, 1e6);
        _tokens[t].mint(address(_PAYOUT), r + s);
        reward[t][k] += r;
        seized[t] += s;
        _payReward(t, k);
        _paySeized(t);
        vm.prank(_CORE);
        _PAYOUT.creditSeizure(address(_tokens[t]), _recipients[k], r, s);
    }

    function creditReferral(
        uint8 token_,
        uint8 recipient_,
        uint80 protocol_,
        uint80 reward_
    ) external {
        if (!enabled || !selected) return;
        uint256 t = bound(token_, 0, 1);
        uint256 k = bound(recipient_, 0, 2);
        uint256 p = bound(protocol_, 0, 1e6);
        uint256 r = bound(reward_, 0, 1e6);
        _tokens[t].mint(address(_PAYOUT), p + r);
        fee[t] += p;
        referral[t][k] += r;
        referralEarned[t][k] += r;
        if (p != 0) _payFee(t);
        if (r != 0) _payReferral(t, k);
        vm.prank(_CORE);
        _PAYOUT.creditFee(address(_tokens[t]), p, _recipients[k], r);
    }

    function retry(uint8 token_, uint8 recipient_) external {
        uint256 t = bound(token_, 0, 1);
        uint256 k = bound(recipient_, 0, 2);
        uint256 beforeTotal = total(t);
        if (k == feeRoute) _payFee(t);
        if (k == 0) _paySeized(t);
        _payReward(t, k);
        _payReferral(t, k);
        assertEq(
            _PAYOUT.transferPendingPayout(address(_tokens[t]), _recipients[k]),
            beforeTotal - total(t),
            "Retry pays only independently modelled successful buckets"
        );
    }

    function setBlocked(uint8 token_, uint8 recipient_, bool value_) external {
        uint256 t = bound(token_, 0, 1);
        uint256 k = bound(recipient_, 0, 2);
        blocked[t][k] = value_;
        _tokens[t].setTransferReverts(_recipients[k], value_);
    }

    function setFeeRoute(bool distributor_) external {
        _PAYOUT.setSendFeesToDistributor(distributor_);
        feeRoute = distributor_ ? 1 : 0;
    }

    function setEnabled(bool enabled_) external {
        if (enabled_ == enabled) return;
        if (enabled_) _PAYOUT.enable("");
        else _PAYOUT.disable("");
        enabled = enabled_;
    }

    function setSelected(bool selected_) external {
        if (selected_ == selected || (selected_ && !enabled)) return;
        IBurnerLoansCore(_CORE).setPayout(selected_ ? address(_PAYOUT) : _REPLACEMENT);
        selected = selected_;
    }

    function setReferralShare(uint16 bps_) external {
        referralBps = uint16(bound(bps_, 0, 10_000));
        _RISK.setReferralFeeBps(referralBps);
    }

    function setReferrer(uint8 recipient_, bool allowed_) external {
        uint256 k = bound(recipient_, 0, 2);
        allowed[k] = allowed_;
        _RISK.setReferrerAllowed(_recipients[k], allowed_);
    }

    function donate(uint8 token_, uint80 amount_) external {
        uint256 t = bound(token_, 0, 1);
        uint256 amount = bound(amount_, 0, 1e6);
        surplus[t] += amount;
        _tokens[t].mint(address(_PAYOUT), amount);
    }

    /// @dev Deterministic fresh-state seed, excluded from the random action selectors.
    function seedMaximumReferral() external {
        assertEq(_tokens[0].totalSupply(), 0, "Maximum seed requires a fresh token");
        assertEq(total(0), 0, "Maximum seed requires an empty ledger");
        blocked[0][2] = true;
        _tokens[0].setTransferReverts(_recipients[2], true);
        referral[0][2] = type(uint256).max;
        referralEarned[0][2] = type(uint256).max;
        _tokens[0].mint(address(_PAYOUT), type(uint256).max);
        vm.prank(_CORE);
        _PAYOUT.creditFee(address(_tokens[0]), 0, _recipients[2], type(uint256).max);
    }

    function rescueSurplus(uint8 token_, uint80 amount_) external {
        uint256 t = bound(token_, 0, 1);
        uint256 amount = bound(amount_, 0, 1e6);
        _tokens[t].mint(address(_PAYOUT), amount);
        surplus[t] += amount;
        paid[t][3] += surplus[t];
        surplus[t] = 0;
        _PAYOUT.rescue(address(_tokens[t]), _DESTINATION);
    }

    function rescuePending(uint8 token_, uint8 recipient_, uint256 quantity_) external {
        uint256 t = bound(token_, 0, 1);
        uint256 k = bound(recipient_, 0, 2);
        uint256 available = entitlement(t, k);
        if (available == 0) return;
        uint256 quantity = bound(quantity_, 1, available);
        uint256 remaining = quantity;
        uint256 debit = remaining < reward[t][k] ? remaining : reward[t][k];
        reward[t][k] -= debit;
        remaining -= debit;
        if (k == feeRoute) {
            debit = remaining < fee[t] ? remaining : fee[t];
            fee[t] -= debit;
            remaining -= debit;
        }
        if (k == 0) {
            debit = remaining < seized[t] ? remaining : seized[t];
            seized[t] -= debit;
            remaining -= debit;
        }
        assertLe(remaining, referral[t][k], "Validated model remainder is referral entitlement");
        referral[t][k] -= remaining;
        referralRescued[t][k] += remaining;
        paid[t][3] += quantity;
        _PAYOUT.rescuePendingPayout(address(_tokens[t]), _recipients[k], _DESTINATION, quantity);
    }

    function entitlement(uint256 t_, uint256 k_) public view returns (uint256 amount) {
        amount = reward[t_][k_] + referral[t_][k_];
        if (k_ == feeRoute) amount += fee[t_];
        if (k_ == 0) amount += seized[t_];
    }

    function total(uint256 t_) public view returns (uint256) {
        return
            fee[t_] +
            seized[t_] +
            reward[t_][0] +
            reward[t_][1] +
            reward[t_][2] +
            referral[t_][0] +
            referral[t_][1] +
            referral[t_][2];
    }

    function _payFee(uint256 t_) internal {
        if (blocked[t_][feeRoute]) return;
        paid[t_][feeRoute] += fee[t_];
        fee[t_] = 0;
    }

    function _paySeized(uint256 t_) internal {
        if (blocked[t_][0]) return;
        paid[t_][0] += seized[t_];
        seized[t_] = 0;
    }

    function _payReward(uint256 t_, uint256 k_) internal {
        if (blocked[t_][k_]) return;
        paid[t_][k_] += reward[t_][k_];
        reward[t_][k_] = 0;
    }

    function _payReferral(uint256 t_, uint256 k_) internal {
        if (blocked[t_][k_]) return;
        paid[t_][k_] += referral[t_][k_];
        referralPaid[t_][k_] += referral[t_][k_];
        referral[t_][k_] = 0;
    }
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth)

// forge-lint: disable-end(missing-zero-check)
