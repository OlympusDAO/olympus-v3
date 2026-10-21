// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";

/// @notice Records payouts when a token transfer to the destination fails.
/// @dev A failed delivery must not roll back a borrower action or seizure. The source transfer
///      into Burner Loans remains strict; an asset that blocks Burner Loans itself cannot be used.
library BurnerLoansPayouts {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using SafeERC20Exact for IERC20;

    /// @notice Unpaid obligations and addresses needed to enumerate direct retries.
    struct State {
        mapping(address token => uint256 amount) pendingFees;
        // Seized backing follows the current TRSRY module when retried, never the address at seizure.
        mapping(address token => uint256 amount) pendingSeizedCollateral;
        mapping(address token => mapping(address keeper => uint256 amount)) pendingKeeperRewards;
        // Aggregate reserve excludes all pending obligations from unreserved rescue.
        mapping(address token => uint256 amount) totalPending;
        EnumerableSet.AddressSet pendingTokens;
        mapping(address token => EnumerableSet.AddressSet keepers) pendingKeeperRecipients;
    }

    /// @notice Collects an exact caller fee and attempts the current fee destination.
    /// @dev Reverts if:
    ///      - The payer's transfer fails or the facility receives an inexact amount.
    ///      - Adding the new fee to its pending balance overflows.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Fee token.
    /// @param payer_ Account paying the fee.
    /// @param recipient_ Current fee destination.
    /// @param amount_ Fee collected in token units.
    function collectFee(
        State storage state_,
        address token_,
        address payer_,
        address recipient_,
        uint256 amount_
    ) public {
        if (amount_ == 0) return;
        // The fee debt is recorded at face value. Reject a token transfer that credits less,
        // even if that token was exact when collateral was originally deposited.
        IERC20(token_).safeTransferFromExact(payer_, address(this), amount_);
        state_.pendingFees[token_] += amount_;
        state_.totalPending[token_] += amount_;
        state_.pendingTokens.add(token_);
        transferPendingFee(state_, token_, recipient_);
    }

    /// @notice Accrues a seizure reward to its original keeper and attempts delivery.
    /// @dev Reverts if:
    ///      - Adding the reward to the keeper's pending balance overflows.
    ///      A normal outgoing token transfer failure leaves the reward pending.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Seized token.
    /// @param keeper_ Original keeper entitled to the reward.
    /// @param amount_ New reward in token units.
    /// @return Amount paid immediately or on this retry.
    function queueSeizureReward(
        State storage state_,
        address token_,
        address keeper_,
        uint256 amount_
    ) public returns (uint256) {
        if (amount_ != 0) {
            state_.pendingKeeperRewards[token_][keeper_] += amount_;
            state_.totalPending[token_] += amount_;
            state_.pendingTokens.add(token_);
            state_.pendingKeeperRecipients[token_].add(keeper_);
        }
        return transferPendingSeizureReward(state_, token_, keeper_);
    }

    /// @notice Accrues seized collateral for the current Treasury and attempts delivery.
    /// @dev Reverts if:
    ///      - Adding seized collateral to its pending balance overflows.
    ///      A normal outgoing token transfer failure leaves the collateral pending.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Seized token.
    /// @param treasury_ Current Treasury module address.
    /// @param amount_ New collateral owed in token units.
    /// @return Amount paid immediately or on this retry.
    function queueSeizedCollateral(
        State storage state_,
        address token_,
        address treasury_,
        uint256 amount_
    ) public returns (uint256) {
        if (amount_ != 0) {
            state_.pendingSeizedCollateral[token_] += amount_;
            state_.totalPending[token_] += amount_;
            state_.pendingTokens.add(token_);
        }
        return transferPendingSeizedCollateral(state_, token_, treasury_);
    }

    /// @notice Attempts a keeper's pending seizure reward.
    /// @dev A normal ERC-20 transfer failure returns zero and keeps the obligation.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Seized token.
    /// @param keeper_ Original keeper entitled to the reward.
    /// @return Amount transferred to the keeper, or zero if unpaid.
    function transferPendingSeizureReward(
        State storage state_,
        address token_,
        address keeper_
    ) public returns (uint256) {
        uint256 amount = state_.pendingKeeperRewards[token_][keeper_];
        if (amount == 0) return 0;
        // Keep the keeper's fixed-address obligation intact when delivery fails.
        if (!IERC20(token_).trySafeTransfer(keeper_, amount)) {
            emit IBurnerLoans.PayoutDeferred(
                token_,
                keeper_,
                IBurnerLoans.PayoutKind.SeizureReward,
                amount
            );
            return 0;
        }
        state_.pendingKeeperRewards[token_][keeper_] = 0;
        state_.totalPending[token_] -= amount;
        state_.pendingKeeperRecipients[token_].remove(keeper_);
        _removeTokenIfPaid(state_, token_);
        emit IBurnerLoans.PayoutTransferred(
            token_,
            keeper_,
            IBurnerLoans.PayoutKind.SeizureReward,
            amount
        );
        return amount;
    }

    /// @notice Attempts pending seized collateral for the current Treasury.
    /// @dev A normal ERC-20 transfer failure returns zero and keeps the obligation.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Seized token.
    /// @param treasury_ Current Treasury module address.
    /// @return Amount transferred to Treasury, or zero if unpaid.
    function transferPendingSeizedCollateral(
        State storage state_,
        address token_,
        address treasury_
    ) public returns (uint256) {
        uint256 amount = state_.pendingSeizedCollateral[token_];
        if (amount == 0) return 0;
        // Treasury is resolved by the caller on each attempt, including after module upgrades.
        if (!IERC20(token_).trySafeTransfer(treasury_, amount)) {
            emit IBurnerLoans.PayoutDeferred(
                token_,
                treasury_,
                IBurnerLoans.PayoutKind.Seizure,
                amount
            );
            return 0;
        }
        state_.pendingSeizedCollateral[token_] = 0;
        state_.totalPending[token_] -= amount;
        _removeTokenIfPaid(state_, token_);
        emit IBurnerLoans.PayoutTransferred(
            token_,
            treasury_,
            IBurnerLoans.PayoutKind.Seizure,
            amount
        );
        return amount;
    }

    /// @notice Attempts a pending fee for its current routing destination.
    /// @dev A normal ERC-20 transfer failure returns zero and keeps the obligation.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Fee token.
    /// @param recipient_ Current fee destination.
    /// @return Amount transferred to the recipient, or zero if unpaid.
    function transferPendingFee(
        State storage state_,
        address token_,
        address recipient_
    ) public returns (uint256) {
        uint256 amount = state_.pendingFees[token_];
        if (amount == 0) return 0;
        // Fees follow the current role destination; a failed attempt leaves the same amount owed.
        if (!IERC20(token_).trySafeTransfer(recipient_, amount)) {
            emit IBurnerLoans.PayoutDeferred(
                token_,
                recipient_,
                IBurnerLoans.PayoutKind.Fee,
                amount
            );
            return 0;
        }
        state_.pendingFees[token_] = 0;
        state_.totalPending[token_] -= amount;
        _removeTokenIfPaid(state_, token_);
        emit IBurnerLoans.PayoutTransferred(
            token_,
            recipient_,
            IBurnerLoans.PayoutKind.Fee,
            amount
        );
        return amount;
    }

    /// @notice Enumerates tokens with at least one pending payout.
    /// @dev Does not revert for an empty set.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @return Tokens with pending obligations.
    function tokens(State storage state_) public view returns (address[] memory) {
        return state_.pendingTokens.values();
    }

    /// @notice Enumerates current fee and Treasury destinations plus original keeper addresses.
    /// @dev Deduplicates destinations; does not revert when no payout is pending for `token_`.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Token owed.
    /// @param feeRecipient_ Current fee destination.
    /// @param treasury_ Current Treasury module address.
    /// @return result Unique recipients with pending obligations for the token.
    function recipients(
        State storage state_,
        address token_,
        address feeRecipient_,
        address treasury_
    ) public view returns (address[] memory result) {
        EnumerableSet.AddressSet storage keeperSet = state_.pendingKeeperRecipients[token_];
        address[] memory keepers = keeperSet.values();
        address[] memory found = new address[](keepers.length + 2);
        uint256 length;
        for (uint256 i; i < keepers.length; ++i) found[length++] = keepers[i];
        bool includeFee = state_.pendingFees[token_] != 0 &&
            feeRecipient_ != address(0) &&
            !keeperSet.contains(feeRecipient_);
        if (includeFee) found[length++] = feeRecipient_;
        if (
            state_.pendingSeizedCollateral[token_] != 0 &&
            treasury_ != address(0) &&
            !keeperSet.contains(treasury_) &&
            (!includeFee || treasury_ != feeRecipient_)
        ) found[length++] = treasury_;
        result = new address[](length);
        for (uint256 i; i < length; ++i) result[i] = found[i];
    }

    /// @dev Removes a token from retry enumeration only after every payout type is settled.
    ///      Does not revert when other payout types remain.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Token to remove once all obligations are settled.
    function _removeTokenIfPaid(State storage state_, address token_) private {
        if (
            state_.pendingFees[token_] == 0 &&
            state_.pendingSeizedCollateral[token_] == 0 &&
            state_.pendingKeeperRecipients[token_].length() == 0
        ) state_.pendingTokens.remove(token_);
    }
}
