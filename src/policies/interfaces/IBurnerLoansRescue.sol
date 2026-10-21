// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Rescue Interface
/// @notice Rescue operations and previews for unreserved tokens and deferred payouts.
interface IBurnerLoansRescue {
    /// @notice The rescue asset is not a deployed token contract.
    error BurnerLoans_InvalidAsset(address token);

    /// @notice The destination cannot receive this rescue.
    error BurnerLoans_InvalidRescueDestination(address destination);

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

    /// @notice Pending fee was redirected.
    /// @param token Token owed.
    /// @param destination Rescue recipient.
    /// @param amount Amount debited from this liability.
    event PendingFeeRescued(address indexed token, address indexed destination, uint256 amount);

    /// @notice Pending seizure was redirected.
    /// @param token Token owed.
    /// @param destination Rescue recipient.
    /// @param amount Amount debited from this liability.
    event PendingSeizureRescued(address indexed token, address indexed destination, uint256 amount);

    /// @notice A requested rescue exceeds the recipient's combined pending payout.
    /// @param token Token owed.
    /// @param requested Proposed rescue amount.
    /// @param available Available amount in the recipient's combined entitlement.
    error BurnerLoans_InsufficientPendingPayout(
        address token,
        uint256 requested,
        uint256 available
    );

    /// @notice Transfers the full unreserved token balance to a specified destination.
    /// @dev Local disablement does not block rescue. A zero surplus is a no-op.
    /// @param token_ Token to recover.
    /// @param destination_ Rescue recipient.
    function rescue(address token_, address destination_) external;

    /// @notice Redirects an exact amount owed to one payout recipient.
    /// @dev Callable while locally disabled; resolves role recipients at execution.
    ///      Debits keeper reward, fee, then seized collateral.
    ///      Emits one per-kind event for each nonzero debit and transfers the total once.
    /// @param token_ Token owed.
    /// @param recipient_ Recipient currently owed the pending payout.
    /// @param destination_ Recipient of the rescued tokens.
    /// @param amount_ Exact positive amount, at most pendingPayout(token_, recipient_).
    function rescuePendingPayout(
        address token_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external;

    /// @notice Returns the full unreserved token balance available for rescue.
    /// @dev Returns zero when token custody does not exceed aggregate pending payouts.
    /// @param token_ Token to inspect.
    /// @param destination_ Proposed rescue recipient.
    /// @return amount Amount available for rescue.
    function previewRescue(
        address token_,
        address destination_
    ) external view returns (uint256 amount);

    /// @notice Validates the requested amount against the recipient's combined pending payout.
    /// @dev Permissionless and callable while locally disabled; does not predict token transfer acceptance.
    /// @param token_ Token owed.
    /// @param recipient_ Recipient currently owed the pending payout.
    /// @param destination_ Rescue destination.
    /// @param amount_ Exact positive amount requested.
    /// @return available Current combined amount owed to the recipient.
    function previewRescuePendingPayout(
        address token_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external view returns (uint256 available);
}
