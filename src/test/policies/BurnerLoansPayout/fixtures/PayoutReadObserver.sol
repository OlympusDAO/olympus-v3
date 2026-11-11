// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansPayoutHarness} from "./BurnerLoansPayoutHarness.sol";

/// @dev Records public accounting during a strict recovery transfer, after its reserve debit.
contract PayoutReadObserver {
    BurnerLoansPayoutHarness internal immutable _PAYOUT;
    uint256 public fee;
    uint256 public seized;
    uint256 public total;
    uint256 public reward;
    uint256 public referral;
    uint256 public totalReferral;
    uint256 public totalKeeperReward;
    bool public tokenIndexed;
    bool public keeperIndexed;
    bool public referrerIndexed;

    constructor(BurnerLoansPayoutHarness payout_) {
        _PAYOUT = payout_;
    }

    function observe(address token_, address keeper_) external {
        (fee, totalReferral, seized, totalKeeperReward, total) = _PAYOUT.pendingAmounts(token_);
        reward = _PAYOUT.keeperReward(token_, keeper_);
        referral = _PAYOUT.pendingReferralFee(token_, keeper_);
        tokenIndexed = _PAYOUT.hasPendingToken(token_);
        keeperIndexed = _PAYOUT.hasPendingKeeper(token_, keeper_);
        referrerIndexed = _PAYOUT.hasPendingReferrer(token_, keeper_);
    }
}
