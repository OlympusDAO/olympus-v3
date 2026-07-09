// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title IYieldRepurchaseFacilityV2
/// @notice The interface for the Multi-Asset Yield Repurchase Facility (YRF) policy.
/// @dev The facility periodically withdraws yield from a whitelist of ERC4626 reserve
///      vaults and uses it to buy OHM on Bond Protocol SDA markets. Purchased OHM is
///      burned, and the recovered backing value is added to the backing vault's weekly
///      budget to fund subsequent buybacks.
interface IYieldRepurchaseFacilityV2 {
    // ============ EVENTS ============ //

    /// @notice Emitted when a bond market is created for a reserve asset.
    /// @param vault The ERC4626 vault that funds the market.
    /// @param marketId The bond market identifier.
    /// @param payoutToken The token the market pays out: the vault's reserve token for a
    ///        redeem-to-reserve vault, or the vault itself for a sell-shares vault.
    /// @param bidAmount The capacity of the market, denominated in the payout token.
    event RepoMarket(
        address indexed vault,
        uint256 indexed marketId,
        address indexed payoutToken,
        uint256 bidAmount
    );

    /// @notice Emitted when the projected next-week yield is updated for a vault.
    /// @param reserve The underlying reserve token of the vault.
    /// @param nextYield The projected yield, in the reserve token decimals.
    event NextYieldSet(address indexed reserve, uint256 nextYield);

    /// @notice Emitted when the buyback share for a vault is updated.
    /// @param vault The ERC4626 vault.
    /// @param newShare The share of yield allocated to buybacks (`1e18` = 100%).
    event YieldBuybackShareSet(address indexed vault, uint256 newShare);

    /// @notice Emitted when a reserve asset is added to the whitelist.
    /// @param vault The ERC4626 vault.
    /// @param reserve The underlying reserve token of the vault.
    /// @param yieldBuybackShare The initial buyback share for the asset (`1e18` = 100%).
    event AssetAdded(address indexed vault, address indexed reserve, uint256 yieldBuybackShare);

    /// @notice Emitted when a reserve asset is removed from the whitelist.
    /// @param vault The ERC4626 vault.
    event AssetRemoved(address indexed vault);

    /// @notice Emitted when a reserve asset is enabled.
    /// @param vault The ERC4626 vault.
    event AssetEnabled(address indexed vault);

    /// @notice Emitted when a reserve asset is disabled.
    /// @param vault The ERC4626 vault.
    event AssetDisabled(address indexed vault);

    /// @notice Emitted when the backing oracle is updated.
    /// @param backingOracle The new backing oracle.
    event BackingOracleSet(address indexed backingOracle);

    /// @notice Emitted when the primary backing vault is updated.
    /// @param backingVault The new backing vault.
    event BackingVaultSet(address indexed backingVault);

    /// @notice Emitted when the Bond Protocol auctioneer and teller are updated.
    /// @param bondAuctioneer The new Bond Protocol SDA auctioneer.
    /// @param teller The new Bond Protocol teller.
    event BondContractsSet(address indexed bondAuctioneer, address indexed teller);

    /// @notice Emitted when the initial discount is updated.
    /// @param initialDiscount The new initial discount (`1e18` = 100%).
    event InitialDiscountSet(uint256 initialDiscount);

    /// @notice Emitted when a Clearinghouse receivables offset is updated.
    /// @param clearinghouse The Clearinghouse address.
    /// @param offset The new cumulative offset.
    event ClearinghouseOffsetSet(address indexed clearinghouse, uint256 offset);

    /// @notice Emitted when a Clearinghouse is skipped during the weekly yield computation
    ///         because its reserve token does not match the backing vault's reserve, or it
    ///         does not expose the `reserve()` getter.
    /// @param clearinghouse The Clearinghouse address.
    event ClearinghouseDebtTokenMismatch(address indexed clearinghouse);

    /// @notice Emitted when a vault redemption attempt fails. The redemption is skipped
    ///         and retried on a later cycle.
    /// @param vault The ERC4626 vault.
    /// @param shares The number of shares the facility attempted to redeem.
    event RedeemFailed(address indexed vault, uint256 shares);

    /// @notice Emitted when bond market creation fails for a vault. The budget is
    ///         preserved and market creation is retried on the next daily cycle.
    /// @param vault The ERC4626 vault the market would have been funded from.
    /// @param bidAmount The capacity the market would have been created with.
    event MarketCreationFailed(address indexed vault, uint256 bidAmount);

    /// @notice Emitted when the weekly prefund cannot withdraw the full budget shortfall
    ///         because the treasury holds fewer vault shares than required.
    /// @dev The week proceeds on the smaller funded amount. The unfunded gap remains in
    ///      `weeklyBudgetRemaining` and the prefund is retried at the next weekly reset.
    /// @param vault The ERC4626 vault.
    /// @param sharesRequested The share amount required to fully fund the weekly budget.
    /// @param sharesWithdrawn The share amount actually withdrawn from the treasury.
    event PrefundShortfall(address indexed vault, uint256 sharesRequested, uint256 sharesWithdrawn);

    /// @notice Emitted when the projected yield is overridden.
    /// @param reserve The underlying reserve token of the vault.
    /// @param previousYield The previous projected yield value.
    /// @param newYield The new projected yield value.
    event NextYieldAdjusted(address indexed reserve, uint256 previousYield, uint256 newYield);

    /// @notice Emitted when accumulated OHM purchases are burned and the corresponding
    ///         backing is recycled.
    /// @param ohmBurned The amount of OHM burned, in OHM decimals.
    /// @param backingWithdrawn The amount of reserve withdrawn from the backing vault,
    ///        in the backing vault's reserve decimals.
    event OhmPurchasesProcessed(uint256 ohmBurned, uint256 backingWithdrawn);

    // ============ ERRORS ============ //

    /// @notice Thrown when the enable payload length does not match the expected layout.
    error IYieldRepurchaseFacilityV2_InvalidEnableDataLength();

    /// @notice Thrown when an asset operation references a vault that is not registered.
    /// @param vault The vault address that is not registered.
    error IYieldRepurchaseFacilityV2_AssetNotRegistered(address vault);

    /// @notice Thrown when adding a vault whose reserve token is already used by another
    ///         registered vault.
    /// @param vault The vault being added.
    /// @param reserve The reserve token already taken by another vault.
    error IYieldRepurchaseFacilityV2_DuplicateReserve(address vault, address reserve);

    /// @notice Thrown when adding a vault that is already registered.
    /// @param vault The vault that is already registered.
    error IYieldRepurchaseFacilityV2_AssetAlreadyRegistered(address vault);

    /// @notice Thrown when an asset operation requires the asset to be disabled.
    /// @param vault The vault that is still enabled.
    error IYieldRepurchaseFacilityV2_AssetEnabled(address vault);

    /// @notice Thrown when an asset operation requires the asset to be enabled.
    /// @param vault The vault that is disabled.
    error IYieldRepurchaseFacilityV2_AssetDisabled(address vault);

    /// @notice Thrown when a vault is removed or disabled while still being used as
    ///         the `backingVault`.
    /// @param vault The vault that is currently set as the backing vault.
    error IYieldRepurchaseFacilityV2_VaultIsBackingVault(address vault);

    /// @notice Thrown when setting a sell-shares vault as the backing vault. The backing vault
    ///         must be redeemable so that backing can be recovered as its reserve token.
    /// @param vault The vault that cannot be the backing vault.
    error IYieldRepurchaseFacilityV2_BackingVaultCannotSellShares(address vault);

    /// @notice Thrown when adding a sell-shares vault whose share decimals do not match its
    ///         reserve decimals. The bond market prices the shares using the reserve decimals, so
    ///         the two must be equal.
    /// @param vault The vault being added.
    error IYieldRepurchaseFacilityV2_SellSharesDecimalsMismatch(address vault);

    /// @notice Thrown when the initial discount is greater than or equal to `1e18` (100%).
    error IYieldRepurchaseFacilityV2_InitialDiscountTooHigh();

    /// @notice Thrown when the yield buyback share exceeds `1e18` (100%).
    error IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh();

    /// @notice Thrown when `adjustNextYield` would increase a non-zero `nextYield` by more
    ///         than 10%.
    error IYieldRepurchaseFacilityV2_TooMuchIncrease();

    /// @notice Thrown when a Clearinghouse receivables offset would exceed the current
    ///         `principalReceivables` value.
    /// @param clearinghouse The Clearinghouse address.
    /// @param offset The offset that would be set.
    /// @param principalReceivables The current `principalReceivables` of the Clearinghouse.
    error IYieldRepurchaseFacilityV2_OffsetExceedsReceivables(
        address clearinghouse,
        uint256 offset,
        uint256 principalReceivables
    );

    /// @notice Thrown by IBondCallback hooks that this facility does not support.
    error IYieldRepurchaseFacilityV2_NotSupported();

    /// @notice Thrown by the bond callback when the resolved market is not owned by this facility.
    /// @param marketId The market identifier received by the callback.
    error IYieldRepurchaseFacilityV2_UnknownMarket(uint256 marketId);

    /// @notice Thrown by the bond callback when the caller is not the configured teller, and
    ///         by the self-redeem helper when the caller is not the facility itself.
    /// @param caller The unexpected caller.
    error IYieldRepurchaseFacilityV2_InvalidCaller(address caller);

    /// @notice Thrown by the self-redeem helper when a vault delivers less reserve than its
    ///         own `previewRedeem` promise for the redeemed shares.
    /// @param vault The vault.
    /// @param expected The reserve amount promised by `previewRedeem`.
    /// @param received The reserve amount actually delivered.
    error IYieldRepurchaseFacilityV2_InsufficientRedeem(
        address vault,
        uint256 expected,
        uint256 received
    );

    /// @notice Thrown when adding a vault whose reserve token reports more than 18 decimals.
    /// @param vault The vault being added.
    /// @param decimals The reserve decimals reported by the vault's underlying asset.
    error IYieldRepurchaseFacilityV2_UnsupportedDecimals(address vault, uint8 decimals);

    /// @notice Thrown when the `PRICE` module does not report 18 decimals.
    /// @dev The facility compares the oracle price directly against the 18-decimal backing
    ///      value, so it requires the oracle to also report 18 decimals.
    /// @param decimals The decimals reported by the `PRICE` module.
    error IYieldRepurchaseFacilityV2_UnsupportedOracleDecimals(uint8 decimals);

    /// @notice Thrown when attempting to rescue OHM, a registered vault or a registered
    ///         reserve token.
    /// @param token The token that cannot be rescued.
    error IYieldRepurchaseFacilityV2_CannotRescue(address token);

    // ============ STRUCTS ============ //

    /// @notice The per-reserve configuration and state tracked by the facility.
    /// @param vault The ERC4626 vault address.
    /// @param reserve The cached underlying reserve token of the vault.
    /// @param reserveDecimals The cached decimals of `reserve`.
    /// @param sellShares True to sell the vault's shares on bond markets (for a vault
    ///        whose shares cannot be synchronously redeemed, e.g. sUSDe); false redeems the shares
    ///        to the reserve and sells the reserve.
    /// @param isAssetEnabled True if the asset participates in the periodic cycle.
    /// @param yieldBuybackShare The share of yield routed to buybacks (`1e18` = 100%).
    /// @param lastReserveBalance The protocol-owned reserve balance snapshotted at the
    ///        last weekly reset, in `reserveDecimals`.
    /// @param lastConversionRate The vault conversion rate snapshotted at the last weekly
    ///        reset: the reserve value of `10 ** reserveDecimals` vault shares.
    /// @param nextYield The projected yield to roll into `weeklyBudgetRemaining` at the
    ///        next weekly reset, in `reserveDecimals`.
    /// @param weeklyBudgetRemaining The remaining buyback budget for the current week,
    ///        in `reserveDecimals`.
    /// @param prefundedShares The vault shares withdrawn from the treasury and held by
    ///        the facility for buybacks.
    /// @param prefundedReserve The reserve redeemed from the prefunded shares (or received
    ///        through backing recycling) and held by the facility until it is paid out
    ///        through a bond market, in `reserveDecimals`.
    struct ReserveAsset {
        address vault;
        address reserve;
        uint8 reserveDecimals;
        bool sellShares;
        bool isAssetEnabled;
        uint256 yieldBuybackShare;
        uint256 lastReserveBalance;
        uint256 lastConversionRate;
        uint256 nextYield;
        uint256 weeklyBudgetRemaining;
        uint256 prefundedShares;
        uint256 prefundedReserve;
    }

    // ============ ADMIN FUNCTIONS ============ //

    /// @notice Whitelist a new ERC4626 vault for yield extraction and buybacks.
    /// @param vault_ The ERC4626 vault to whitelist.
    /// @param yieldBuybackShare_ The share of yield routed to buybacks (`1e18` = 100%).
    /// @param initialReserveBalance_ The initial `lastReserveBalance` snapshot, in reserve decimals.
    /// @param initialConversionRate_ The initial `lastConversionRate` snapshot (the reserve
    ///        value of `10 ** reserveDecimals` vault shares).
    /// @param sellShares_ True to sell the vault's shares on bond markets (for a vault
    ///        whose shares cannot be synchronously redeemed, e.g. sUSDe); false redeems the shares
    ///        to the reserve and sells the reserve.
    function addAsset(
        address vault_,
        uint256 yieldBuybackShare_,
        uint256 initialReserveBalance_,
        uint256 initialConversionRate_,
        bool sellShares_
    ) external;

    /// @notice Remove a vault from the whitelist and return any leftover balance to the treasury.
    /// @param vault_ The ERC4626 vault to remove.
    function removeAsset(address vault_) external;

    /// @notice Set the backing oracle policy address.
    /// @param backingOracle_ The new backing oracle.
    function setBackingOracle(address backingOracle_) external;

    /// @notice Set the primary backing vault used for backing recycling.
    /// @param vault_ The vault to use as the backing vault.
    function setBackingVault(address vault_) external;

    /// @notice Update the Bond Protocol SDA auctioneer and teller addresses.
    /// @param bondAuctioneer_ The new bond auctioneer.
    /// @param teller_ The new bond teller.
    function setBondContracts(address bondAuctioneer_, address teller_) external;

    /// @notice Set a Clearinghouse receivables offset (used to neutralize phantom
    ///         receivables that would otherwise inflate the projected yield).
    /// @dev Restricted to the admin role.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @param offset_ The new cumulative offset.
    function setClearinghouseOffset(address clearinghouse_, uint256 offset_) external;

    // ============ MANAGER FUNCTIONS ============ //

    /// @notice Adjust the buyback share for a registered vault.
    /// @param vault_ The vault whose share is updated.
    /// @param newShare_ The new share (`1e18` = 100%).
    function setYieldBuybackShare(address vault_, uint256 newShare_) external;

    /// @notice Adjust the initial discount applied to bond market initial price.
    /// @param initialDiscount_ The new initial discount (`1e18` = 100%).
    function setInitialDiscount(uint256 initialDiscount_) external;

    /// @notice Override the projected next-week yield for a vault.
    /// @dev Adjusting an existing non-zero projection is capped at a 10% increase and is
    ///      available to the yrf_manager or admin role. Seeding the projection from zero is
    ///      unbounded and is therefore restricted to the admin role.
    /// @param vault_ The vault whose projection is overridden.
    /// @param newNextYield_ The new projected yield.
    function adjustNextYield(address vault_, uint256 newNextYield_) external;

    /// @notice Increase the cumulative offset of a Clearinghouse.
    /// @dev Restricted to the yrf_manager role.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @param additionalOffset_ The amount to add to the existing offset.
    function increaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external;

    /// @notice Re-enable a previously disabled vault.
    /// @dev Refreshes the vault's balance and conversion rate snapshots, so the projection
    ///      computed at the next weekly reset covers only the period after the vault is
    ///      re-enabled and the yield accrued while the vault was disabled is retained by
    ///      the treasury.
    /// @param vault_ The vault to enable.
    function enableAsset(address vault_) external;

    /// @notice Pause a vault. While paused the vault is skipped by `execute()`.
    /// @param vault_ The vault to pause.
    function disableAsset(address vault_) external;

    // ============ VIEW FUNCTIONS ============ //

    /// @notice Returns the list of currently registered vault addresses.
    function getVaults() external view returns (address[] memory);

    /// @notice Returns the full state for a registered vault.
    /// @param vault_ The vault to inspect.
    /// @return config The full per-asset configuration and state.
    function getAssetConfig(address vault_) external view returns (ReserveAsset memory config);

    /// @notice Project the next-week yield for a single vault.
    /// @dev For the `backingVault`, the projection also includes the global Clearinghouse
    ///      receivables interest contribution. For other vaults, only the vault appreciation
    ///      is included. The result is scaled by the vault's `yieldBuybackShare`.
    ///
    /// @param vault_ The vault to inspect.
    /// @return yield The projected yield in the vault's reserve decimals.
    function getNextYield(address vault_) external view returns (uint256 yield);

    /// @notice Return the protocol-owned reserve balance of a vault.
    /// @dev For the `backingVault`, the balance includes TRSRY and all active Clearinghouses.
    ///      For other vaults, only TRSRY is included. Balances held by the facility itself
    ///      are excluded.
    ///
    /// @param vault_ The vault to inspect.
    /// @return balance The protocol-owned reserve balance in the vault's reserve decimals.
    function getReserveBalance(address vault_) external view returns (uint256 balance);

    /// @notice Returns the reserve token associated with a bond market created by this facility.
    /// @dev Returns `address(0)` for unknown markets.
    ///
    /// @param marketId_ The bond market identifier.
    /// @return reserve The reserve token, or `address(0)` if the market is unknown.
    function marketReserves(uint256 marketId_) external view returns (address reserve);

    /// @notice Returns the cumulative offset applied to a Clearinghouse's
    ///         `principalReceivables` when computing yield.
    /// @param clearinghouse_ The Clearinghouse address.
    function clearinghouseOffset(address clearinghouse_) external view returns (uint256);

    /// @notice The Bond Protocol teller used by this facility.
    function teller() external view returns (address);

    /// @notice The Bond Protocol SDA auctioneer used by this facility.
    function bondAuctioneer() external view returns (address);

    /// @notice The OHM backing oracle used by this facility.
    function backingOracle() external view returns (address);

    /// @notice The primary backing vault used for backing recycling.
    function backingVault() external view returns (address);

    /// @notice The initial discount applied to bond market initial price (`1e18` = 100%).
    function initialDiscount() external view returns (uint256);

    /// @notice The accumulated OHM purchased through bond markets but not yet processed.
    function ohmPurchased() external view returns (uint256);

    /// @notice The running epoch counter, in the range `[0, 21)`.
    function epoch() external view returns (uint48);
}
