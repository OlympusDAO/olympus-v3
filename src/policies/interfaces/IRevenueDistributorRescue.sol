// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Revenue Distributor Rescue Interface
/// @notice Rescue operations and previews for never-listed assets and deferred distributions.
interface IRevenueDistributorRescue {
    /// @notice The destination cannot receive this rescue.
    /// @param destination Invalid rescue destination.
    error RevenueDistributor_InvalidRescueDestination(address destination);

    /// @notice A managed asset cannot use the never-listed surplus rescue path.
    /// @param asset Managed asset address.
    error RevenueDistributor_AssetManaged(address asset);

    /// @notice A pending rescue must transfer a positive amount.
    error RevenueDistributor_InvalidRescueAmount();

    /// @notice The requested amount exceeds the recipient's combined pending payout.
    /// @param asset Asset whose distribution is pending.
    /// @param requested Amount requested for rescue.
    /// @param available Amount currently owed in the recipient's combined entitlement.
    error RevenueDistributor_InsufficientPendingDistribution(
        address asset,
        uint256 requested,
        uint256 available
    );

    /// @notice The full balance of a never-listed token was rescued.
    /// @param asset Recovered asset.
    /// @param destination Recipient of the rescued token.
    /// @param amount Amount transferred in asset units.
    event AssetRescued(address indexed asset, address indexed destination, uint256 amount);

    /// @notice Pending asset route distribution was redirected.
    /// @param asset Token owed.
    /// @param originalRecipient Original payout recipient.
    /// @param destination Rescue recipient.
    /// @param amount Amount debited from this liability.
    event PendingAssetRouteRescued(
        address indexed asset,
        address indexed originalRecipient,
        address indexed destination,
        uint256 amount
    );

    /// @notice Pending repurchase was redirected.
    /// @param asset Token owed.
    /// @param destination Rescue recipient.
    /// @param amount Amount debited from this liability.
    event PendingRepurchaseRescued(
        address indexed asset,
        address indexed destination,
        uint256 amount
    );

    /// @notice Pending treasury was redirected.
    /// @param asset Token owed.
    /// @param destination Rescue recipient.
    /// @param amount Amount debited from this liability.
    event PendingTreasuryRescued(
        address indexed asset,
        address indexed destination,
        uint256 amount
    );

    /// @notice Sends the full live balance of a never-listed asset to a specified destination.
    /// @dev Admin or the selected config operator may call.
    /// @param asset_ Never-listed asset to rescue.
    /// @param destination_ Recipient of the rescued token.
    function rescue(address asset_, address destination_) external;

    /// @notice Returns the live balance of a never-listed asset available for rescue.
    /// @param asset_ Never-listed asset to inspect.
    /// @param destination_ Proposed rescue recipient.
    /// @return amount Full amount currently available.
    function previewRescue(
        address asset_,
        address destination_
    ) external view returns (uint256 amount);

    /// @notice Redirects an exact amount owed to one payout recipient.
    /// @dev Callable while locally disabled; resolves role recipients at execution.
    ///      Debits asset route, repurchase, then Treasury.
    ///      Emits one per-kind event for each nonzero debit and transfers the total once.
    /// @param asset_ Token owed.
    /// @param recipient_ Recipient currently owed the pending payout.
    /// @param destination_ Recipient of the rescued tokens.
    /// @param amount_ Exact positive amount, at most pendingPayout(asset_, recipient_).
    function rescuePendingPayout(
        address asset_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external;

    /// @notice Validates the requested amount against the recipient's combined pending payout.
    /// @dev Permissionless and callable while locally disabled; does not predict token transfer acceptance.
    /// @param asset_ Token owed.
    /// @param recipient_ Recipient currently owed the pending payout.
    /// @param destination_ Rescue destination.
    /// @param amount_ Exact positive amount requested.
    /// @return available Current combined amount owed to the recipient.
    function previewRescuePendingPayout(
        address asset_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external view returns (uint256 available);
}
