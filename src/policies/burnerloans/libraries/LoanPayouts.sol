// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";

// Contracts
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

/// @notice Records payouts when a token transfer to the destination fails.
/// @dev A failed delivery must not roll back a borrower action or seizure. The source transfer
///      into Burner Loans remains strict; an asset that blocks Burner Loans itself cannot be used.
library LoanPayouts {
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
    /// @param recipient_ Current fee destination.
    /// @param amount_ Fee collected in token units.
    function creditFee(
        State storage state_,
        address token_,
        address recipient_,
        uint256 amount_
    ) internal {
        if (amount_ == 0) return;
        // Record the liability before attempting delivery. A failed optional transfer retains both
        // the source bucket and aggregate reserve, so recovery cannot mistake owed tokens for surplus.
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
    /// @return uint256 Amount paid immediately or on this retry.
    function queueSeizureReward(
        State storage state_,
        address token_,
        address keeper_,
        uint256 amount_
    ) internal returns (uint256) {
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
    /// @param treasury_ Local Treasury route for protocol-owned seized collateral.
    /// @param amount_ New collateral owed in token units.
    /// @return uint256 Amount paid immediately or on this retry.
    function queueSeizedCollateral(
        State storage state_,
        address token_,
        address treasury_,
        uint256 amount_
    ) internal returns (uint256) {
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
    /// @return uint256 Amount transferred to the keeper, or zero if unpaid.
    function transferPendingSeizureReward(
        State storage state_,
        address token_,
        address keeper_
    ) internal returns (uint256) {
        return
            _transferPending(state_, token_, keeper_, IBurnerLoansPayout.PayoutKind.SeizureReward);
    }

    /// @notice Attempts pending seized collateral for the current Treasury.
    /// @dev A normal ERC-20 transfer failure returns zero and keeps the obligation.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Seized token.
    /// @param treasury_ Local Treasury route for protocol-owned seized collateral.
    /// @return uint256 Amount transferred to Treasury, or zero if unpaid.
    function transferPendingSeizedCollateral(
        State storage state_,
        address token_,
        address treasury_
    ) internal returns (uint256) {
        return _transferPending(state_, token_, treasury_, IBurnerLoansPayout.PayoutKind.Seizure);
    }

    /// @notice Attempts a pending fee for its current routing destination.
    /// @dev A normal ERC-20 transfer failure returns zero and keeps the obligation.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Fee token.
    /// @param recipient_ Current fee destination.
    /// @return uint256 Amount transferred to the recipient, or zero if unpaid.
    function transferPendingFee(
        State storage state_,
        address token_,
        address recipient_
    ) internal returns (uint256) {
        return _transferPending(state_, token_, recipient_, IBurnerLoansPayout.PayoutKind.Fee);
    }

    /// @notice Enumerates tokens with at least one pending payout.
    /// @dev Does not revert for an empty set.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @return address[] Tokens with pending obligations.
    function tokens(State storage state_) internal view returns (address[] memory) {
        return state_.pendingTokens.values();
    }

    /// @dev Removes a token from retry enumeration only after every payout type is settled.
    ///      Does not revert when other payout types remain.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Token to remove once all obligations are settled.
    function _removeTokenIfPaid(State storage state_, address token_) private {
        if (state_.totalPending[token_] == 0) state_.pendingTokens.remove(token_);
    }

    /// @notice Validates the recovery token and destination.
    /// @dev Reverts if:
    ///      - The rescue asset is not a deployed token contract.
    ///      - The destination cannot receive this rescue.
    ///      Reads without state changes; errors from dependency views propagate.
    /// @param token_ Token whose balance or payout accounting is used.
    /// @param destination_ Recovery destination.
    /// @param configurator_ Selected Config authority.
    /// @param kernel_ Kernel supplying modules and governance authority.
    function _validateRescueAddresses(
        address token_,
        address destination_,
        address configurator_,
        address kernel_
    ) private view {
        if (token_.code.length == 0) revert IBurnerLoansErrors.BurnerLoans_InvalidAsset(token_);
        if (
            destination_ == address(0) ||
            destination_ == address(this) ||
            destination_ == token_ ||
            destination_ == configurator_ ||
            destination_ == kernel_
        ) revert IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination(destination_);
    }

    /// @notice Returns the entitlement using current fee/Treasury routes and fixed keeper identity.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param state_ Payout buckets and indexes owned by Payout.
    /// @param token_ Token whose balance or payout accounting is used.
    /// @param recipient_ Final output recipient or pending entitlement holder.
    /// @param feeRecipient_ Current local fee route.
    /// @param treasury_ Local Treasury route for protocol-owned seized collateral.
    /// @return amount Combined pending fee, seized backing and keeper entitlement for this recipient.
    function pendingAmount(
        State storage state_,
        address token_,
        address recipient_,
        address feeRecipient_,
        address treasury_
    ) internal view returns (uint256 amount) {
        amount = state_.pendingKeeperRewards[token_][recipient_];
        if (recipient_ == feeRecipient_) amount += state_.pendingFees[token_];
        if (recipient_ == treasury_) amount += state_.pendingSeizedCollateral[token_];
    }

    /// @notice Quotes unreserved custody surplus available for recovery.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param state_ Payout buckets and indexes owned by Payout.
    /// @param token_ Token whose balance or payout accounting is used.
    /// @param destination_ Recovery destination.
    /// @param configurator_ Selected Config authority.
    /// @param kernel_ Kernel supplying modules and governance authority.
    /// @return uint256 Unreserved surplus available for recovery in token units.
    function previewRescue(
        State storage state_,
        address token_,
        address destination_,
        address configurator_,
        address kernel_
    ) internal view returns (uint256) {
        _validateRescueAddresses(token_, destination_, configurator_, kernel_);
        uint256 balance = IERC20(token_).balanceOf(address(this));
        return balance > state_.totalPending[token_] ? balance - state_.totalPending[token_] : 0;
    }

    /// @notice Quotes a validated pending entitlement available for recovery.
    /// @dev Reverts if:
    ///      - A required address is zero.
    ///      - An operation was requested with a zero token amount.
    ///      - A requested rescue exceeds the recipient's combined pending payout.
    ///      Reads without state changes; errors from dependency views propagate.
    /// @param state_ Payout buckets and indexes owned by Payout.
    /// @param token_ Token whose balance or payout accounting is used.
    /// @param recipient_ Final output recipient or pending entitlement holder.
    /// @param destination_ Recovery destination.
    /// @param amount_ Token amount in the operation's documented token units.
    /// @param feeRecipient_ Current local fee route.
    /// @param treasury_ Local Treasury route for protocol-owned seized collateral.
    /// @param configurator_ Selected Config authority.
    /// @param kernel_ Kernel supplying modules and governance authority.
    /// @return available Validated recipient entitlement in token units.
    function previewRescuePendingPayout(
        State storage state_,
        address token_,
        address recipient_,
        address destination_,
        uint256 amount_,
        address feeRecipient_,
        address treasury_,
        address configurator_,
        address kernel_
    ) internal view returns (uint256 available) {
        _validateRescueAddresses(token_, destination_, configurator_, kernel_);
        if (recipient_ == address(0)) revert IBurnerLoansErrors.BurnerLoans_ZeroAddress();
        if (amount_ == 0) revert IBurnerLoansCore.BurnerLoansCore_ZeroAmount();
        available = pendingAmount(state_, token_, recipient_, feeRecipient_, treasury_);
        if (amount_ > available)
            revert IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout(
                token_,
                amount_,
                available
            );
    }

    /// @notice Transfers only unreserved surplus to an authorized recovery destination.
    /// @dev Reverts if:
    ///      - Surplus preview rejects the token, destination or reserve state.
    ///      - The strict surplus transfer fails.
    ///
    /// @dev The caller applies recovery authorization and settlement guards before invoking this helper.
    ///      A failed transfer rolls back the operation.
    ///
    /// @param state_ Payout buckets and indexes owned by Payout.
    /// @param token_ Token whose balance or payout accounting is used.
    /// @param destination_ Recovery destination.
    /// @param configurator_ Selected Config authority.
    /// @param kernel_ Kernel supplying modules and governance authority.
    function rescue(
        State storage state_,
        address token_,
        address destination_,
        address configurator_,
        address kernel_
    ) internal {
        uint256 amount = previewRescue(state_, token_, destination_, configurator_, kernel_);
        if (amount == 0) return;
        SafeERC20.safeTransfer(IERC20(token_), destination_, amount);
        emit IBurnerLoansPayout.AssetRescued(token_, destination_, amount);
    }

    /// @notice Redirects an existing pending entitlement with reserve-safe accounting.
    /// @dev Reverts if:
    ///      - Pending-payout preview rejects the destination, amount or available entitlement.
    ///      - The strict transfer fails.
    ///
    /// @dev The caller applies recovery authorization and settlement guards before invoking this helper.
    ///      Reserve accounting and transfer roll back together on failure.
    ///
    /// @param state_ Payout buckets and indexes owned by Payout.
    /// @param token_ Token whose balance or payout accounting is used.
    /// @param recipient_ Final output recipient or pending entitlement holder.
    /// @param destination_ Recovery destination.
    /// @param amount_ Token amount in the operation's documented token units.
    /// @param feeRecipient_ Current local fee route.
    /// @param treasury_ Local Treasury route for protocol-owned seized collateral.
    /// @param configurator_ Selected Config authority.
    /// @param kernel_ Kernel supplying modules and governance authority.
    function rescuePendingPayout(
        State storage state_,
        address token_,
        address recipient_,
        address destination_,
        uint256 amount_,
        address feeRecipient_,
        address treasury_,
        address configurator_,
        address kernel_
    ) internal {
        // Validates that amount_ is positive and fits the recipient's combined pending payout.
        previewRescuePendingPayout(
            state_,
            token_,
            recipient_,
            destination_,
            amount_,
            feeRecipient_,
            treasury_,
            configurator_,
            kernel_
        );
        // One recipient can hold several kinds of entitlement. Consume keeper reward, then fees,
        // then Treasury backing so the combined rescue debits each source and the reserve exactly once.
        uint256 seizureReward = Math.min(amount_, state_.pendingKeeperRewards[token_][recipient_]);
        uint256 fee;
        if (recipient_ == feeRecipient_) {
            fee = Math.min(amount_ - seizureReward, state_.pendingFees[token_]);
        }
        uint256 seizure = amount_ - seizureReward - fee;

        if (seizureReward != 0) {
            state_.pendingKeeperRewards[token_][recipient_] -= seizureReward;
            if (state_.pendingKeeperRewards[token_][recipient_] == 0)
                state_.pendingKeeperRecipients[token_].remove(recipient_);
            emit IBurnerLoansPayout.PendingSeizureRewardRescued(
                token_,
                recipient_,
                destination_,
                seizureReward
            );
        }
        if (fee != 0) {
            state_.pendingFees[token_] -= fee;
            emit IBurnerLoansPayout.PendingFeeRescued(token_, destination_, fee);
        }
        if (seizure != 0) {
            // The validated entitlement includes seized collateral only for the current Treasury.
            state_.pendingSeizedCollateral[token_] -= seizure;
            emit IBurnerLoansPayout.PendingSeizureRescued(token_, destination_, seizure);
        }
        state_.totalPending[token_] -= amount_;
        if (state_.totalPending[token_] == 0) state_.pendingTokens.remove(token_);
        SafeERC20.safeTransfer(IERC20(token_), destination_, amount_);
    }

    /// @dev All payout kinds share one fail-soft transfer path under the Payout guard.
    /// @param state_ Payout buckets and indexes owned by Payout.
    /// @param token_ Token whose balance or payout accounting is used.
    /// @param recipient_ Final output recipient or pending entitlement holder.
    /// @param kind_ Fee, seized backing or keeper entitlement bucket.
    /// @return amount Amount successfully delivered in token units; zero on no entitlement or delivery failure.
    function _transferPending(
        State storage state_,
        address token_,
        address recipient_,
        IBurnerLoansPayout.PayoutKind kind_
    ) private returns (uint256 amount) {
        // 1. Resolve the entire entitlement for this payout kind.
        if (kind_ == IBurnerLoansPayout.PayoutKind.Fee) amount = state_.pendingFees[token_];
        else if (kind_ == IBurnerLoansPayout.PayoutKind.Seizure)
            amount = state_.pendingSeizedCollateral[token_];
        else amount = state_.pendingKeeperRewards[token_][recipient_];
        if (amount == 0) return 0;
        // 2. Attempt delivery; retain every bucket/index on failure. The caller holds Payout's guard.
        if (!IERC20(token_).trySafeTransfer(recipient_, amount)) {
            emit IBurnerLoansPayout.PayoutDeferred(token_, recipient_, kind_, amount);
            return 0;
        }
        // 3. Successful delivery clears the bucket and its recipient/token indexes exactly once.
        if (kind_ == IBurnerLoansPayout.PayoutKind.Fee) state_.pendingFees[token_] = 0;
        else if (kind_ == IBurnerLoansPayout.PayoutKind.Seizure)
            state_.pendingSeizedCollateral[token_] = 0;
        else {
            state_.pendingKeeperRewards[token_][recipient_] = 0;
            state_.pendingKeeperRecipients[token_].remove(recipient_);
        }
        state_.totalPending[token_] -= amount;
        _removeTokenIfPaid(state_, token_);
        emit IBurnerLoansPayout.PayoutTransferred(token_, recipient_, kind_, amount);
    }
}
