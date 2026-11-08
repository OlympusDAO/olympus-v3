// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @notice Replaceable fee and liquidation custody; yield routing preserves direct DepositManager payments.
interface IBurnerLoansPayout {
    // ========== EVENTS ========== //

    /// @notice The full unreserved balance was sent to a rescue destination.
    /// @param token Recovered token.
    /// @param destination Rescue recipient.
    /// @param amount Transferred amount.
    event AssetRescued(address indexed token, address indexed destination, uint256 amount);

    /// @notice An original keeper's pending seizure reward was redirected.
    /// @param token Token owed.
    /// @param originalRecipient Original payout recipient.
    /// @param destination Rescue recipient.
    /// @param amount Amount debited from this liability.
    event PendingSeizureRewardRescued(
        address indexed token,
        address indexed originalRecipient,
        address indexed destination,
        uint256 amount
    );

    /// @notice An original referrer's pending referral fee was redirected.
    /// @param token Token owed.
    /// @param originalRecipient Original referrer whose entitlement was debited.
    /// @param destination Rescue recipient.
    /// @param amount Amount debited from this liability.
    event PendingReferralFeeRescued(
        address indexed token,
        address indexed originalRecipient,
        address indexed destination,
        uint256 amount
    );

    /// @notice Pending protocol fee was redirected.
    /// @param token Token owed.
    /// @param destination Rescue recipient.
    /// @param amount Amount debited from this liability.
    event PendingFeeRescued(address indexed token, address indexed destination, uint256 amount);

    /// @notice Pending seizure was redirected.
    /// @param token Token owed.
    /// @param destination Rescue recipient.
    /// @param amount Amount debited from this liability.
    event PendingSeizureRescued(address indexed token, address indexed destination, uint256 amount);

    /// @notice A token transfer failed, leaving this amount owed by payout type.
    /// @param token Token held by Burner Loans.
    /// @param recipient Destination selected for the attempted payout.
    /// @param kind Accounting bucket that remains owed.
    /// @param amount Amount still owed in token units.
    event PayoutDeferred(
        address indexed token,
        address indexed recipient,
        PayoutKind indexed kind,
        uint256 amount
    );

    /// @notice A payout was delivered to the current recipient selected for its type.
    /// @param token Token transferred from Burner Loans.
    /// @param recipient Destination that received the payout.
    /// @param kind Accounting bucket cleared by the transfer.
    /// @param amount Amount transferred in token units.
    event PayoutTransferred(
        address indexed token,
        address indexed recipient,
        PayoutKind indexed kind,
        uint256 amount
    );

    event RevenueDistributorSet(address indexed distributor);

    event SendFeesToDistributorSet(bool enabled);

    event SendYieldToDistributorSet(bool enabled);

    // ========== ERRORS ========== //

    /// @notice A payout allocation or retry names zero or Payout itself as its recipient.
    /// @param recipient Unsupported payout recipient.
    error BurnerLoansPayout_InvalidRecipient(address recipient);

    /// @notice A requested rescue exceeds the recipient's combined pending payout.
    /// @param token Token owed.
    /// @param requested Proposed rescue amount.
    /// @param available Available amount in the recipient's combined entitlement.
    error BurnerLoans_InsufficientPendingPayout(
        address token,
        uint256 requested,
        uint256 available
    );

    /// @notice Token balance cannot cover existing reserves and the new credit.
    /// @param token Token received by Payout.
    /// @param balance Actual token balance.
    /// @param expected Required token balance including the new credit.
    error BurnerLoansPayout_InsufficientBalance(address token, uint256 balance, uint256 expected);

    /// @notice Combining payout reserves/allocations exceeds uint256.
    /// @param existing Existing reserve or first allocation.
    /// @param additional Incoming allocation.
    error BurnerLoansPayout_AmountOverflow(uint256 existing, uint256 additional);

    /// @notice The distributor is inactive, belongs to another Kernel or lacks the required interface.
    /// @param distributor Rejected revenue distributor.
    error BurnerLoans_InvalidRevenueDistributor(address distributor);

    /// @notice A distributor route is enabled without a selected distributor.
    error BurnerLoans_RevenueDistributorRequired();

    // ========== ENUMS ========== //

    /// @notice Source of a deferred token payout.
    enum PayoutKind {
        Fee,
        Seizure,
        SeizureReward,
        Referral
    }

    // ========== FUNCTIONS ========== //

    /// @notice Current Treasury resolved through Payout's Kernel.
    /// @return recipient Current Treasury module.
    function treasury() external view returns (address recipient);

    /// @notice Selected optional RevenueDistributor.
    /// @return distributor Optional revenue destination.
    function revenueDistributor() external view returns (address distributor);

    /// @notice Whether fee payouts use RevenueDistributor.
    /// @return enabled Current fee routing flag.
    function sendFeesToDistributor() external view returns (bool enabled);

    /// @notice Whether direct yield payments use RevenueDistributor.
    /// @return enabled Current yield routing flag.
    function sendYieldToDistributor() external view returns (bool enabled);

    /// @notice OCG ADMIN directly selects the optional distributor; delegated operators cannot.
    /// @param distributor Active enabled same-Kernel distributor, or zero when both routing flags are false.
    function setRevenueDistributor(address distributor) external;

    /// @notice Config or OCG ADMIN updates fee routing, including the destination of pending fees.
    /// @param enabled Whether fees use the distributor instead of Treasury.
    function setSendFeesToDistributor(bool enabled) external;

    /// @notice Config or OCG ADMIN updates direct yield routing.
    /// @param enabled Whether subsequent yield uses the distributor instead of Treasury.
    function setSendYieldToDistributor(bool enabled) external;

    /// @notice Validates a distributor's interface, Kernel, activation and enabled state.
    /// @param distributor Proposed revenue recipient.
    function validateRevenueDistributor(address distributor) external view;

    /// @notice Validates a destination for a positive payout allocation or a direct retry.
    /// @dev Permissionless and independent of Payout's lifecycle and routing configuration.
    /// @param recipient Proposed payout destination.
    function validatePayoutRecipient(address recipient) external view;

    /// @notice Recipient for a direct DepositManager yield payment; Payout never receives yield.
    /// @return recipient Current Treasury or configured RevenueDistributor.
    function yieldRecipient() external view returns (address recipient);

    /// @notice Reserves separately allocated protocol and referral fees and attempts delivery.
    /// @dev Positive allocations cannot name this Payout as recipient.
    /// @param token Token received directly from the fee payer.
    /// @param protocolFee Protocol allocation in raw token units, routed to the current fee destination.
    /// @param referrer Original recipient of the referral allocation; zero when no referrer was supplied.
    /// @param referralFee Referral allocation in raw token units; zero when referrer is zero.
    function creditFee(
        address token,
        uint256 protocolFee,
        address referrer,
        uint256 referralFee
    ) external;

    /// @notice Records received liquidation proceeds and attempts their allocated payouts.
    /// @dev Positive keeper or Treasury allocations cannot name this Payout as recipient.
    /// @param token Underlying collateral or vault share token received from DepositManager.
    /// @param keeper Original keeper entitled to the reward.
    /// @param reward Keeper allocation in output token units.
    /// @param remainder Treasury allocation in output token units.
    function creditSeizure(
        address token,
        address keeper,
        uint256 reward,
        uint256 remainder
    ) external;

    /// @notice Permissionless retry of this Payout's obligations, including after replacement or Core disablement.
    /// @param token Token whose pending obligations are retried.
    /// @param recipient Current protocol destination, original keeper or original referrer being paid.
    /// @return transferred Total successfully paid across eligible payout buckets, in token units.
    function transferPendingPayout(
        address token,
        address recipient
    ) external returns (uint256 transferred);

    /// @notice Sends the Payout's unreserved surplus to an authorized rescue destination.
    /// @dev Available while locally disabled; zero surplus is a no-op.
    /// @param token Token whose unreserved balance is rescued.
    /// @param destination Account receiving the surplus.
    function rescue(address token, address destination) external;

    /// @notice Redirects part of a recipient's pending entitlement using rescue authority.
    /// @dev Consumes keeper rewards, protocol fees, seized collateral, then referral fees.
    ///      Emits one event per nonzero bucket and transfers once. Available while locally disabled.
    /// @param token Token whose pending entitlement is redirected.
    /// @param recipient Original keeper, original referrer or current protocol destination holding the entitlement.
    /// @param destination Account receiving the redirected payout.
    /// @param amount Entitlement to redirect, in token units.
    function rescuePendingPayout(
        address token,
        address recipient,
        address destination,
        uint256 amount
    ) external;

    /// @notice Returns one recipient's combined pending entitlement for a token.
    /// @param token Token in which the entitlement is owed.
    /// @param recipient Current protocol destination, original keeper or original referrer.
    /// @return amount Total eligible pending amount in token units.
    function pendingRecipientAmount(
        address token,
        address recipient
    ) external view returns (uint256 amount);

    /// @notice Enumerates tokens with outstanding payout obligations.
    /// @return tokens Tokens with a nonzero total reserved amount.
    function getPendingPayoutTokens() external view returns (address[] memory tokens);

    /// @notice Returns every pending payout bucket and their aggregate reserve across all recipients for a token.
    /// @param token Token whose reserves are queried.
    /// @return protocolFee Outstanding protocol fees in token units.
    /// @return referralFee Outstanding referral fees across all original recipients, in token units.
    /// @return seized Outstanding Treasury liquidation proceeds in token units.
    /// @return keeperReward Outstanding keeper rewards across all original recipients, in token units.
    /// @return total Total outstanding obligations, including keeper rewards and referral fees, in token units.
    function pendingAmounts(
        address token
    )
        external
        view
        returns (
            uint256 protocolFee,
            uint256 referralFee,
            uint256 seized,
            uint256 keeperReward,
            uint256 total
        );

    /// @notice Returns one original keeper's unpaid reward for a token.
    /// @param token Token in which the reward is owed.
    /// @param keeper Original keeper entitled to the reward.
    /// @return amount Pending keeper reward in raw token units.
    function pendingKeeperReward(
        address token,
        address keeper
    ) external view returns (uint256 amount);

    /// @notice Enumerates original keepers with outstanding rewards for a token.
    /// @param token Token whose reward recipients are queried.
    /// @return keepers Original keepers with nonzero pending rewards.
    function getPendingKeepers(address token) external view returns (address[] memory keepers);

    /// @notice Returns an original referrer's unpaid referral fee.
    /// @param token Token in which the referral fee is owed.
    /// @param recipient Original referrer entitled to the fee.
    /// @return amount Pending referral fee in raw token units.
    function pendingReferralFee(
        address token,
        address recipient
    ) external view returns (uint256 amount);

    /// @notice Enumerates original referrers with nonzero unpaid referral fees.
    /// @param token Token whose referral recipients are queried.
    /// @return recipients Original referrers with nonzero unpaid referral fees.
    function getPendingReferralRecipients(
        address token
    ) external view returns (address[] memory recipients);

    /// @notice Enumerates the current protocol destinations, original keepers and referrers owed by this Payout.
    /// @param token Token whose eligible recipients are queried.
    /// @return recipients Distinct addresses currently entitled to pending payouts.
    function getPendingPayoutRecipients(
        address token
    ) external view returns (address[] memory recipients);

    /// @notice Returns only this Payout's unreserved surplus.
    /// @dev Returns zero when the token balance does not exceed aggregate pending payouts.
    /// @param token Token whose balance and reserves are inspected.
    /// @param destination Proposed rescue recipient.
    /// @return amount Unreserved surplus in token units.
    function previewRescue(
        address token,
        address destination
    ) external view returns (uint256 amount);

    /// @notice Returns the complete pending entitlement after validating a proposed redirect.
    /// @dev Permissionless and available while locally disabled; token transfer acceptance is checked on execution.
    /// @param token Token whose pending entitlement is inspected.
    /// @param recipient Original keeper, original referrer or current protocol destination holding the entitlement.
    /// @param destination Proposed redirected payout recipient.
    /// @param amount Proposed redirect amount in token units.
    /// @return available Total eligible pending entitlement in token units.
    function previewRescuePendingPayout(
        address token,
        address recipient,
        address destination,
        uint256 amount
    ) external view returns (uint256 available);
}
