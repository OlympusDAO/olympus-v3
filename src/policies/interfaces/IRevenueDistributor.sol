// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Revenue Distributor Interface
/// @notice Asset-specific allocation of protocol fee and yield receipts.
interface IRevenueDistributor {
    /// @notice Listing state of an asset's distribution route.
    enum AssetState {
        /// @notice The asset has never had a configured route.
        NeverListed,
        /// @notice The asset has an active route.
        Active,
        /// @notice The asset was listed, then its route was disabled.
        Retired
    }

    /// @notice One configured route to a non-Treasury recipient for an asset.
    struct AssetRoute {
        /// @notice Recipient of this route's allocation.
        address recipient;
        /// @notice Allocation in basis points of the asset's unreserved receipts.
        uint16 bps;
    }

    /// @notice The asset address is zero or has no code.
    /// @param asset Invalid asset address.
    error RevenueDistributor_InvalidAsset(address asset);

    /// @notice A recipient or basis-point entry cannot be used in a route.
    /// @param recipient Invalid recipient address.
    error RevenueDistributor_InvalidRecipient(address recipient);

    /// @notice A configured recipient's allocation has zero basis points.
    /// @param recipient Recipient with the zero share.
    error RevenueDistributor_ZeroRecipientBasisPoints(address recipient);

    /// @notice A recipient appears more than once in one distribution.
    /// @param recipient Repeated recipient address.
    error RevenueDistributor_DuplicateRecipient(address recipient);

    /// @notice Non-Treasury shares exceed the 10,000 basis-point total.
    /// @param totalBps Proposed total allocation in basis points.
    error RevenueDistributor_InvalidBasisPoints(uint256 totalBps);

    /// @notice The asset has no active distribution.
    /// @param asset Inactive asset address.
    error RevenueDistributor_AssetNotActive(address asset);

    /// @notice The distributor policy is inactive in its Kernel.
    error RevenueDistributor_PolicyInactive();

    /// @notice A caller other than admin or the selected config operator attempted a restricted action.
    /// @param caller Unauthorized caller address.
    error RevenueDistributor_UnauthorizedConfigOperator(address caller);

    /// @notice A proposed yield recipient lacks the required policy or interface state.
    /// @param recipient Invalid yield recipient address.
    error RevenueDistributor_InvalidYieldRecipient(address recipient);

    /// @notice The yield recipient cannot receive a share of this asset.
    /// @param recipient Yield recipient address.
    /// @param asset Unsupported asset address.
    error RevenueDistributor_YieldRecipientUnavailable(address recipient, address asset);

    /// @notice The token balance is below already reserved recipient payouts.
    /// @param asset Asset whose balance is below its reserved payouts.
    error RevenueDistributor_InsufficientPayoutBalance(address asset);

    /// @notice An asset's distribution route was set or changed.
    /// @param asset Distributed asset.
    /// @param repurchaseBps Share directed to the yield recipient, in basis points.
    /// @param routes Configured routes to non-Treasury recipients.
    event AssetDistributionSet(address indexed asset, uint16 repurchaseBps, AssetRoute[] routes);

    /// @notice An asset's distribution was disabled and its route cleared.
    /// @param asset Disabled asset.
    event AssetDistributionDisabled(address indexed asset);

    /// @notice The global yield recipient changed.
    /// @param recipient New yield recipient.
    event YieldRecipientSet(address indexed recipient);

    /// @notice Emitted for each nonzero payout after its transfer succeeds.
    /// @param asset Distributed asset.
    /// @param recipient Recipient paid.
    /// @param amount Amount transferred in asset units.
    event Distributed(address indexed asset, address indexed recipient, uint256 amount);

    /// @notice A distribution transfer failed and its allocated amount remains reserved.
    /// @param asset Distributed asset.
    /// @param recipient Recipient still owed.
    /// @param amount Amount still owed in asset units.
    event DistributionDeferred(address indexed asset, address indexed recipient, uint256 amount);

    /// @notice Sets or reconfigures a managed asset distribution. Admin or the selected config operator may call.
    /// @dev Treasury receives rounding dust.
    /// @param asset_ Asset whose route is configured.
    /// @param repurchaseBps_ Share sent to the yield recipient, in basis points.
    /// @param routes_ Configured routes to non-Treasury recipients.
    function setAssetRoutes(
        address asset_,
        uint16 repurchaseBps_,
        AssetRoute[] calldata routes_
    ) external;

    /// @notice Validates an asset-route update without changing distributor state.
    /// @param asset_ Asset whose route would be configured.
    /// @param repurchaseBps_ Share that would be sent to the yield recipient, in basis points.
    /// @param routes_ Proposed routes to non-Treasury recipients.
    function validateSetAssetRoutes(
        address asset_,
        uint16 repurchaseBps_,
        AssetRoute[] calldata routes_
    ) external view;

    /// @notice Disables an active asset and clears its route without making it unmanaged.
    /// @dev Admin or the selected config operator may call.
    /// @param asset_ Asset whose route is disabled.
    function disableAssetRoutes(address asset_) external;

    /// @notice Validates that an asset route can be disabled without changing distributor state.
    /// @param asset_ Asset whose route would be disabled.
    function validateDisableAssetRoutes(address asset_) external view;

    /// @notice Sets the global yield-repurchase recipient, or clears it when no active route uses it.
    /// @dev Admin or the selected config operator may call. Clearing directs unpaid repurchase shares
    ///      to current Treasury. A nonzero replacement
    ///      must support assets with unpaid repurchase shares, including retired assets.
    /// @param recipient_ New yield recipient, or zero to route its share to Treasury.
    function setYieldRecipient(address recipient_) external;

    /// @notice Validates a yield-recipient update without changing distributor state.
    /// @param recipient_ Proposed yield recipient, or zero for Treasury fallback.
    function validateSetYieldRecipient(address recipient_) external view;

    /// @notice Allocates unreserved receipts and attempts the current route's recipients.
    /// @param asset_ Active asset to distribute.
    function distribute(address asset_) external;

    /// @notice Retries the reserved payout for one recipient, including current role destinations.
    /// @dev Callable for a disabled asset while the distributor is enabled and Kernel-active.
    ///      A failed transfer remains reserved.
    /// @param asset_ Asset owed.
    /// @param recipient_ Recipient whose pending distribution is retried.
    function transferPendingPayout(address asset_, address recipient_) external;

    /// @notice Returns the amount currently owed to a recipient for an asset.
    /// @param asset_ Asset owed.
    /// @param recipient_ Recipient to inspect.
    /// @return Amount owed to the recipient in asset units.
    function pendingPayout(address asset_, address recipient_) external view returns (uint256);

    /// @notice Returns assets that have at least one reserved payout, including retired assets.
    /// @return Assets with pending distributions.
    function getPendingPayoutAssets() external view returns (address[] memory);

    /// @notice Returns current destinations with reserved payouts for an asset.
    /// @param asset_ Asset owed.
    /// @return Recipients with pending distributions for the asset.
    function getPendingPayoutRecipients(address asset_) external view returns (address[] memory);

    /// @notice Returns whether an asset has never been listed, is active, or was disabled.
    /// @param asset_ Asset to inspect.
    /// @return Listing state of the asset.
    function assetState(address asset_) external view returns (AssetState);

    /// @notice Returns the active assets.
    /// @return Assets with active distribution routes.
    function getActiveAssets() external view returns (address[] memory);

    /// @notice Returns the number of active assets.
    /// @return Number of assets with active routes.
    function getActiveAssetCount() external view returns (uint256);

    /// @notice Returns one active asset by index.
    /// @param index_ Index in the active asset set.
    /// @return Asset at the index.
    function getActiveAssetAt(uint256 index_) external view returns (address);

    /// @notice Returns the stored active distribution, or an empty route after disablement.
    /// @param asset_ Asset whose route is queried.
    /// @return repurchaseBps Share directed to the yield recipient, in basis points.
    /// @return routes Configured routes to non-Treasury recipients.
    function getAssetDistribution(
        address asset_
    ) external view returns (uint16 repurchaseBps, AssetRoute[] memory routes);

    /// @notice Hashes an asset's distribution, state, and yield recipient for stale-action checks.
    /// @param asset_ Asset whose configuration is hashed.
    /// @return Hash of the current configuration state.
    function assetDistributionHash(address asset_) external view returns (bytes32);

    /// @notice Returns the current yield recipient.
    /// @return Current yield recipient, or zero for Treasury fallback.
    function yieldRecipient() external view returns (address);

    /// @notice Returns the current Treasury module address.
    /// @return Current Treasury module address.
    function treasury() external view returns (address);
}
