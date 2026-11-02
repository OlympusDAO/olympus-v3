// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// Tests read state after calls to assert exact effects and rollback.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth)

// Foundry assertTrue checks both nonzero constructor addresses before storage; the linter
// does not recognize that test assertion as a zero check.
// forge-lint: disable-start(missing-zero-check)

// Contracts
import {BurnerLoansPayoutHarness} from "./BurnerLoansPayoutHarness.sol";
import {Test} from "forge-std/Test.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";

/// @dev Two tokens, three overlapping route/keeper identities, optional failures and local pauses.
///      Unit tests separately cover maxima, authorization, Kernel migration and callbacks.
contract PayoutAccountingHandler is Test {
    BurnerLoansPayoutHarness internal immutable _PAYOUT;
    address internal immutable _CORE;
    address internal immutable _DESTINATION;
    MockRevertingTransferToken[2] internal _tokens;
    address[3] internal _recipients;

    uint256[2] public fee;
    uint256[2] public seized;
    uint256[3][2] public reward;
    uint256[4][2] public paid;
    bool[3][2] public blocked;
    uint256 public feeRoute;
    bool public enabled = true;

    constructor(
        BurnerLoansPayoutHarness payout_,
        address core_,
        MockRevertingTransferToken[2] memory tokens_,
        address[3] memory recipients_,
        address destination_
    ) {
        assertTrue(core_ != address(0), "Handler requires a real Core");
        assertTrue(destination_ != address(0), "Handler requires a recovery destination");
        _PAYOUT = payout_;
        _CORE = core_;
        _tokens = tokens_;
        _recipients = recipients_;
        _DESTINATION = destination_;
    }

    function creditFee(uint8 token_, uint80 amount_) external {
        uint256 t = bound(token_, 0, 1);
        uint256 amount = bound(amount_, 0, 1e6);
        if (!enabled) return;
        _tokens[t].mint(address(_PAYOUT), amount);
        fee[t] += amount;
        if (amount != 0) _payFee(t);
        vm.prank(_CORE);
        _PAYOUT.creditFee(address(_tokens[t]), amount);
    }

    function creditSeizure(uint8 token_, uint8 keeper_, uint80 reward_, uint80 seized_) external {
        if (!enabled) return;
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

    function retry(uint8 token_, uint8 recipient_) external {
        uint256 t = bound(token_, 0, 1);
        uint256 k = bound(recipient_, 0, 2);
        uint256 beforeTotal = total(t);
        if (k == feeRoute) _payFee(t);
        if (k == 0) _paySeized(t);
        _payReward(t, k);
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

    function rescueSurplus(uint8 token_, uint80 amount_) external {
        uint256 t = bound(token_, 0, 1);
        uint256 amount = bound(amount_, 0, 1e6);
        _tokens[t].mint(address(_PAYOUT), amount);
        paid[t][3] += amount;
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
            seized[t] -= remaining;
            remaining = 0;
        }
        assertEq(remaining, 0, "Validated model entitlement covers debit");
        paid[t][3] += quantity;
        _PAYOUT.rescuePendingPayout(address(_tokens[t]), _recipients[k], _DESTINATION, quantity);
    }

    function entitlement(uint256 t_, uint256 k_) public view returns (uint256 amount) {
        amount = reward[t_][k_];
        if (k_ == feeRoute) amount += fee[t_];
        if (k_ == 0) amount += seized[t_];
    }

    function total(uint256 t_) public view returns (uint256) {
        return fee[t_] + seized[t_] + reward[t_][0] + reward[t_][1] + reward[t_][2];
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
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth)

// forge-lint: disable-end(missing-zero-check)
