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
        mapping(address token => uint256 amount) pendingProtocolFees;
        // Seized backing follows the current TRSRY module when retried, never the address at seizure.
        mapping(address token => uint256 amount) pendingSeizedCollateral;
        mapping(address token => mapping(address keeper => uint256 amount)) pendingKeeperRewards;
        // Aggregate reserve excludes all pending obligations from unreserved rescue.
        mapping(address token => uint256 amount) totalPending;
        EnumerableSet.AddressSet pendingTokens;
        mapping(address token => EnumerableSet.AddressSet keepers) pendingKeeperRecipients;
        mapping(address token => mapping(address referrer => uint256 amount)) pendingReferralFees;
        mapping(address token => EnumerableSet.AddressSet referrers) pendingReferralRecipients;
        // Aggregate of the fixed-recipient referral buckets, for constant-time reserve queries.
        mapping(address token => uint256 amount) totalPendingReferralFees;
        // Aggregate of the original keepers' reward buckets, maintained on credit, payment and rescue.
        mapping(address token => uint256 amount) totalPendingKeeperRewards;
    }

    /// @notice Reserves both received fee allocations before attempting either delivery.
    /// @dev Reverts if:
    ///      - Adding an allocation to its pending balance or aggregate reserve overflows.
    ///      The caller validates the combined incoming receipt before invoking this helper.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Fee token.
    /// @param recipient_ Current fee destination.
    /// @param protocolFee_ Protocol allocation in raw token units.
    /// @param referrer_ Fixed-original recipient of the referral allocation.
    /// @param referralFee_ Referral allocation in raw token units.
    function creditFee(
        State storage state_,
        address token_,
        address recipient_,
        uint256 protocolFee_,
        address referrer_,
        uint256 referralFee_
    ) internal {
        if (protocolFee_ == 0 && referralFee_ == 0) return;
        state_.pendingProtocolFees[token_] += protocolFee_;
        state_.totalPending[token_] += protocolFee_ + referralFee_;
        state_.pendingTokens.add(token_);
        if (referralFee_ != 0) {
            state_.pendingReferralFees[token_][referrer_] += referralFee_;
            state_.totalPendingReferralFees[token_] += referralFee_;
            state_.pendingReferralRecipients[token_].add(referrer_);
        }
        if (protocolFee_ != 0) transferPendingProtocolFee(state_, token_, recipient_);
        if (referralFee_ != 0) transferPendingReferralFee(state_, token_, referrer_);
    }

    /// @notice Attempts the entire referral fee owed to its original referrer.
    /// @dev A failed optional delivery retains the fully backed obligation and indexes.
    /// @param state_ Payout accounting stored by the calling facility.
    /// @param token_ Token in which the referral fee is owed.
    /// @param referrer_ Fixed-original recipient.
    /// @return uint256 Amount successfully delivered in raw token units.
    function transferPendingReferralFee(
        State storage state_,
        address token_,
        address referrer_
    ) internal returns (uint256) {
        return _transferPending(state_, token_, referrer_, IBurnerLoansPayout.PayoutKind.Referral);
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
            state_.totalPendingKeeperRewards[token_] += amount_;
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
    function transferPendingProtocolFee(
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
    ///      - The token address has no deployed code.
    ///      - The destination is zero, this contract, the token, the configurator or Kernel.
    ///
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

    /// @notice Returns every pending entitlement for a recipient, including fixed referral fees.
    /// @dev Recipient-scoped: includes this account's fixed keeper/referral claims plus any current
    ///      protocol routes it owns. The token-wide pendingAmounts getter instead includes every recipient.
    ///      Rescue preview uses this same complete entitlement; there is no separate rescue-only total.
    /// @param state_ Payout buckets and indexes owned by Payout.
    /// @param token_ Token whose pending obligations are queried.
    /// @param recipient_ Account entitled to the payout.
    /// @param feeRecipient_ Current local fee route.
    /// @param treasury_ Current Treasury route.
    /// @return amount Combined protocol, seized, keeper and referral entitlement.
    function pendingRecipientAmount(
        State storage state_,
        address token_,
        address recipient_,
        address feeRecipient_,
        address treasury_
    ) internal view returns (uint256 amount) {
        amount =
            state_.pendingKeeperRewards[token_][recipient_] +
            state_.pendingReferralFees[token_][recipient_];
        if (recipient_ == feeRecipient_) amount += state_.pendingProtocolFees[token_];
        if (recipient_ == treasury_) amount += state_.pendingSeizedCollateral[token_];
    }

    /// @notice Quotes unreserved custody surplus available for recovery.
    /// @dev Reverts if:
    ///      - The token address has no deployed code.
    ///      - The destination is zero, this contract, the token, the configurator or Kernel.
    ///      - The token balance getter fails or cannot be ABI-decoded.
    ///
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
    /// @dev Reads without state changes; errors from dependency views propagate.
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
        available = pendingRecipientAmount(state_, token_, recipient_, feeRecipient_, treasury_);
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
        // Consume keeper rewards, protocol fees, seized collateral, then referral fees.
        // Preview validated their combined availability. No external calls occur until every debit is recorded.
        uint256 remaining = amount_;
        uint256 debit = Math.min(remaining, state_.pendingKeeperRewards[token_][recipient_]);
        if (debit != 0) {
            state_.pendingKeeperRewards[token_][recipient_] -= debit;
            state_.totalPendingKeeperRewards[token_] -= debit;
            if (state_.pendingKeeperRewards[token_][recipient_] == 0)
                state_.pendingKeeperRecipients[token_].remove(recipient_);
            remaining -= debit;
            emit IBurnerLoansPayout.PendingSeizureRewardRescued(
                token_,
                recipient_,
                destination_,
                debit
            );
        }
        if (recipient_ == feeRecipient_) {
            debit = Math.min(remaining, state_.pendingProtocolFees[token_]);
            if (debit != 0) {
                state_.pendingProtocolFees[token_] -= debit;
                remaining -= debit;
                emit IBurnerLoansPayout.PendingFeeRescued(token_, destination_, debit);
            }
        }
        if (recipient_ == treasury_) {
            debit = Math.min(remaining, state_.pendingSeizedCollateral[token_]);
            if (debit != 0) {
                state_.pendingSeizedCollateral[token_] -= debit;
                remaining -= debit;
                emit IBurnerLoansPayout.PendingSeizureRescued(token_, destination_, debit);
            }
        }
        if (remaining != 0) {
            state_.pendingReferralFees[token_][recipient_] -= remaining;
            state_.totalPendingReferralFees[token_] -= remaining;
            if (state_.pendingReferralFees[token_][recipient_] == 0)
                state_.pendingReferralRecipients[token_].remove(recipient_);
            emit IBurnerLoansPayout.PendingReferralFeeRescued(
                token_,
                recipient_,
                destination_,
                remaining
            );
        }
        state_.totalPending[token_] -= amount_;
        if (state_.totalPending[token_] == 0) state_.pendingTokens.remove(token_);
        SafeERC20.safeTransfer(IERC20(token_), destination_, amount_);
    }

    /// @dev All payout kinds share one fail-soft transfer path under the Payout guard.
    /// @param state_ Payout buckets and indexes owned by Payout.
    /// @param token_ Token whose balance or payout accounting is used.
    /// @param recipient_ Final output recipient or pending entitlement holder.
    /// @param kind_ Fee, seized backing, keeper or referral entitlement bucket.
    /// @return amount Amount successfully delivered in token units; zero on no entitlement or delivery failure.
    function _transferPending(
        State storage state_,
        address token_,
        address recipient_,
        IBurnerLoansPayout.PayoutKind kind_
    ) private returns (uint256 amount) {
        // 1. Resolve the entire entitlement for this payout kind.
        if (kind_ == IBurnerLoansPayout.PayoutKind.Fee) amount = state_.pendingProtocolFees[token_];
        else if (kind_ == IBurnerLoansPayout.PayoutKind.Seizure)
            amount = state_.pendingSeizedCollateral[token_];
        else if (kind_ == IBurnerLoansPayout.PayoutKind.SeizureReward)
            amount = state_.pendingKeeperRewards[token_][recipient_];
        else amount = state_.pendingReferralFees[token_][recipient_];
        if (amount == 0) return 0;
        // 2. Attempt delivery; retain every bucket/index on failure. The caller holds Payout's guard.
        // Payout validates allocation destinations before admitting any new credit.
        if (!IERC20(token_).trySafeTransfer(recipient_, amount)) {
            emit IBurnerLoansPayout.PayoutDeferred(token_, recipient_, kind_, amount);
            return 0;
        }
        // 3. Successful delivery clears the bucket and its recipient/token indexes exactly once.
        if (kind_ == IBurnerLoansPayout.PayoutKind.Fee) state_.pendingProtocolFees[token_] = 0;
        else if (kind_ == IBurnerLoansPayout.PayoutKind.Seizure)
            state_.pendingSeizedCollateral[token_] = 0;
        else if (kind_ == IBurnerLoansPayout.PayoutKind.SeizureReward) {
            state_.pendingKeeperRewards[token_][recipient_] = 0;
            state_.totalPendingKeeperRewards[token_] -= amount;
            state_.pendingKeeperRecipients[token_].remove(recipient_);
        } else {
            state_.pendingReferralFees[token_][recipient_] = 0;
            state_.totalPendingReferralFees[token_] -= amount;
            state_.pendingReferralRecipients[token_].remove(recipient_);
        }
        state_.totalPending[token_] -= amount;
        _removeTokenIfPaid(state_, token_);
        emit IBurnerLoansPayout.PayoutTransferred(token_, recipient_, kind_, amount);
    }
}
