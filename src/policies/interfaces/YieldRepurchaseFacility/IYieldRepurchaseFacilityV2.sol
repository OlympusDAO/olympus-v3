// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title IYieldRepurchaseFacilityV2
/// @notice The interface for the multi-asset Yield Repurchase Facility (YRF) policy. The
///         facility draws yield from registered ERC4626 reserve vaults held by the
///         treasury, spends it through daily Bond Protocol markets that buy OHM, and
///         burns the purchased OHM against a treasury withdrawal priced by the backing
///         oracle.
/// @dev Amount conventions: reserve amounts are denominated in the reserve token's
///      decimals, vault share amounts in the vault's decimals (equal to the reserve
///      decimals for every registered vault), and OHM amounts in the OHM decimals.
///      Percentage parameters are scaled by `1e18` (`1e18` = 100%). The oracle price and
///      the backing value are 18-decimal reserve-per-OHM quotes.
///
///      Role restrictions are stated per function. Functions restricted to the YRF
///      timelock and the admin role are callable by the policy returned by `timelock()`
///      or by an admin role holder; the yrf_admin role reaches them through the
///      timelock's queue. The facility also implements: `IPeriodicTask.execute`,
///      restricted to the heart role; `IBondCallback.callback`, restricted to the
///      configured teller; `IEnabler.enable`, restricted to the admin role, and
///      `IEnabler.disable`, restricted to the emergency and admin roles;
///      `IReEnabler.reEnable`, restricted to the yrf_admin role within the grace window
///      after a disable; and `IBasicRescueable.rescue`, restricted to the yrf_admin and
///      admin roles.
interface IYieldRepurchaseFacilityV2 {
    // ============ EVENTS ============ //

    /// @notice Emitted when a bond market is created for a vault.
    /// @param vault The vault whose budget funds the market.
    /// @param marketId The market ID assigned by the bond auctioneer.
    /// @param payoutToken The token the market pays out: the vault's reserve, or the
    ///        vault share token for a sell-shares asset.
    /// @param bidAmount The market capacity, in payout token units.
    event RepoMarket(
        address indexed vault,
        uint256 indexed marketId,
        address indexed payoutToken,
        uint256 bidAmount
    );

    /// @notice Emitted when the stored next yield of a vault is set.
    /// @param reserve The reserve token of the vault.
    /// @param nextYield The stored next yield, in reserve units.
    event NextYieldSet(address indexed reserve, uint256 nextYield);

    /// @notice Emitted when the yield buyback share of a vault is set.
    /// @param vault The vault whose share is set.
    /// @param newShare The new share (`1e18` = 100%).
    event YieldBuybackShareSet(address indexed vault, uint256 newShare);

    /// @notice Emitted when a vault is registered as a reserve asset.
    /// @param vault The registered vault.
    /// @param reserve The vault's underlying reserve token.
    /// @param yieldBuybackShare The share of the yield routed to buybacks (`1e18` = 100%).
    event AssetAdded(address indexed vault, address indexed reserve, uint256 yieldBuybackShare);

    /// @notice Emitted when a vault is de-registered.
    /// @param vault The removed vault.
    event AssetRemoved(address indexed vault);

    /// @notice Emitted when a registered vault is enabled.
    /// @param vault The enabled vault.
    event AssetEnabled(address indexed vault);

    /// @notice Emitted when a registered vault is disabled.
    /// @param vault The disabled vault.
    event AssetDisabled(address indexed vault);

    /// @notice Emitted when the backing oracle is set.
    /// @param backingOracle The backing oracle policy.
    event BackingOracleSet(address indexed backingOracle);

    /// @notice Emitted when the backing vault is set.
    /// @param backingVault The vault designated as the backing vault.
    event BackingVaultSet(address indexed backingVault);

    /// @notice Emitted when the bond auctioneer and the teller are set.
    /// @param bondAuctioneer The SDA auctioneer used to create markets.
    /// @param teller The teller trusted to invoke the bond callback.
    event BondContractsSet(address indexed bondAuctioneer, address indexed teller);

    /// @notice Emitted when the initial bond market discount is set.
    /// @param initialDiscount The new discount (`1e18` = 100%).
    event InitialDiscountSet(uint256 initialDiscount);

    /// @notice Emitted when the receivables offset of a Clearinghouse is set.
    /// @param clearinghouse The Clearinghouse address.
    /// @param offset The cumulative offset, in the receivables' units.
    event ClearinghouseOffsetSet(address indexed clearinghouse, uint256 offset);

    /// @notice Emitted at each weekly reset for every registry Clearinghouse that does
    ///         not count toward the backing yield.
    /// @param clearinghouse The Clearinghouse address.
    event ClearinghouseDebtTokenMismatch(address indexed clearinghouse);

    /// @notice Emitted when a Clearinghouse is included in the backing yield.
    /// @param clearinghouse The Clearinghouse address.
    event ClearinghouseIncluded(address indexed clearinghouse);

    /// @notice Emitted when a Clearinghouse inclusion is removed.
    /// @param clearinghouse The Clearinghouse address.
    event ClearinghouseExcluded(address indexed clearinghouse);

    /// @notice Emitted when a checked redeem of vault shares fails; the shares are kept
    ///         and no reserve is received.
    /// @param vault The vault whose redeem failed.
    /// @param shares The share amount that was to be redeemed.
    event RedeemFailed(address indexed vault, uint256 shares);

    /// @notice Emitted when a market creation is rejected; the funds stay with the
    ///         facility and the day's market for the vault is skipped.
    /// @param vault The vault whose market was not created.
    /// @param bidAmount The intended market capacity, in payout token units.
    event MarketCreationFailed(address indexed vault, uint256 bidAmount);

    /// @notice Emitted when the treasury balance does not cover the weekly prefund target
    ///         and the withdrawal is capped at the balance.
    /// @param vault The vault being prefunded.
    /// @param sharesRequested The share amount required to cover the weekly budget.
    /// @param sharesWithdrawn The share amount actually withdrawn.
    event PrefundShortfall(address indexed vault, uint256 sharesRequested, uint256 sharesWithdrawn);

    /// @notice Emitted when purchased OHM is burned against a backing withdrawal credited
    ///         to the backing vault's budget.
    /// @param ohmBurned The amount of OHM burned.
    /// @param backingWithdrawn The withdrawal proceeds, in backing reserve units.
    event OhmPurchasesProcessed(uint256 ohmBurned, uint256 backingWithdrawn);

    /// @notice Emitted when the funds held by the facility are returned to the treasury.
    /// @param ohmBurned The amount of purchased OHM that was burned.
    event FundsReturnedToTreasury(uint256 ohmBurned);

    /// @notice Emitted when the sweep of a vault by `returnFundsToTreasury` reverts and
    ///         is skipped; the vault's balances and accounting stay in place and are
    ///         retried by the next call.
    /// @param vault The vault whose sweep was skipped.
    event FundsReturnSkipped(address indexed vault);

    /// @notice Emitted when the weekly reset of a vault reverts and is skipped; the vault
    ///         is retried at the following weekly reset.
    /// @param vault The vault whose reset was skipped.
    event WeeklyResetSkipped(address indexed vault);

    /// @notice Emitted when the daily cycle of a vault reverts and is skipped.
    /// @param vault The vault whose daily cycle was skipped.
    event DailyCycleSkipped(address indexed vault);

    /// @notice Emitted when the processing of the purchased OHM reverts and is skipped;
    ///         the accumulated OHM is retried on the following beats.
    event OhmPurchasesProcessingSkipped();

    /// @notice Emitted when a contribution adds funds to a vault's weekly budget.
    /// @param vault The vault contributed to.
    /// @param contributor The caller that supplied the funds.
    /// @param sharesAdded The vault shares added to the tracked holdings.
    /// @param budgetAdded The redeemable value of the added shares credited to the weekly
    ///        budget, in reserve units.
    event Contributed(
        address indexed vault,
        address indexed contributor,
        uint256 sharesAdded,
        uint256 budgetAdded
    );

    /// @notice Emitted when the running week's buyback budget of a vault is seeded by
    ///         `seedCycle`.
    /// @param vault The seeded vault.
    /// @param weeklyBudget The amount added to the vault's weekly budget, in reserve
    ///        units.
    /// @param epoch The seeded epoch counter.
    event WeeklyBudgetSeeded(address indexed vault, uint256 weeklyBudget, uint48 epoch);

    // ============ ERRORS ============ //

    /// @notice Thrown when the `enable` payload is shorter than the minimum
    ///         `abi.encode(uint256, NextYieldSeed[])` encoding.
    error IYieldRepurchaseFacilityV2_InvalidEnableDataLength();

    /// @notice Thrown when a function targets a vault that is not registered.
    /// @param vault The unregistered vault.
    error IYieldRepurchaseFacilityV2_AssetNotRegistered(address vault);

    /// @notice Thrown when another registered vault uses the same reserve token.
    error IYieldRepurchaseFacilityV2_DuplicateReserve();

    /// @notice Thrown when the vault is already registered.
    error IYieldRepurchaseFacilityV2_AssetAlreadyRegistered();

    /// @notice Thrown when the targeted asset is enabled where a disabled one is required.
    error IYieldRepurchaseFacilityV2_AssetEnabled();

    /// @notice Thrown when the targeted asset is disabled where an enabled one is
    ///         required.
    error IYieldRepurchaseFacilityV2_AssetDisabled();

    /// @notice Thrown when the operation is not allowed on the backing vault.
    error IYieldRepurchaseFacilityV2_VaultIsBackingVault();

    /// @notice Thrown when a sell-shares vault is designated as the backing vault.
    error IYieldRepurchaseFacilityV2_BackingVaultCannotSellShares();

    /// @notice Thrown when the vault's share decimals do not match its reserve decimals.
    error IYieldRepurchaseFacilityV2_VaultDecimalsMismatch();

    /// @notice Thrown when the initial discount is not less than 100% (`1e18`).
    error IYieldRepurchaseFacilityV2_InitialDiscountTooHigh();

    /// @notice Thrown when the yield buyback share exceeds 100% (`1e18`).
    error IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh();

    /// @notice Thrown when the re-enable grace window is configured with a length at or
    ///         above `MAX_GRACE_PERIOD`.
    error IYieldRepurchaseFacilityV2_GracePeriodTooLong();

    /// @notice Thrown when a receivables offset exceeds the Clearinghouse's current
    ///         `principalReceivables`.
    /// @param clearinghouse The Clearinghouse address.
    /// @param offset The rejected cumulative offset.
    /// @param principalReceivables The current `principalReceivables`.
    error IYieldRepurchaseFacilityV2_OffsetExceedsReceivables(
        address clearinghouse,
        uint256 offset,
        uint256 principalReceivables
    );

    /// @notice Thrown when `includeClearinghouse` targets a Clearinghouse that is already
    ///         included in the backing yield.
    error IYieldRepurchaseFacilityV2_ClearinghouseIncluded();

    /// @notice Thrown when `excludeClearinghouse` targets a Clearinghouse that is not
    ///         included in the backing yield.
    error IYieldRepurchaseFacilityV2_ClearinghouseNotIncluded();

    /// @notice Thrown when a next-yield correction targets a stored value that has
    ///         changed since the correction was prepared.
    /// @param vault The vault whose next yield was targeted.
    /// @param expectedNextYield The stored value the correction expected.
    /// @param currentNextYield The stored value found at execution.
    error IYieldRepurchaseFacilityV2_NextYieldMismatch(
        address vault,
        uint256 expectedNextYield,
        uint256 currentNextYield
    );

    /// @notice Thrown when a next-yield correction does not lower the stored value.
    /// @param vault The vault whose next yield was targeted.
    /// @param newNextYield The proposed value.
    /// @param currentNextYield The stored value.
    error IYieldRepurchaseFacilityV2_NextYieldNotDecreased(
        address vault,
        uint256 newNextYield,
        uint256 currentNextYield
    );

    /// @notice Thrown by the `IBondCallback` whitelist management functions, which the
    ///         facility does not support.
    error IYieldRepurchaseFacilityV2_NotSupported();

    /// @notice Thrown when the bond callback targets a market that was not created by the
    ///         facility.
    error IYieldRepurchaseFacilityV2_UnknownMarket();

    /// @notice Thrown when the bond callback is invoked without the facility's OHM
    ///         balance covering the tracked purchased OHM plus the reported input.
    error IYieldRepurchaseFacilityV2_QuoteNotReceived();

    /// @notice Thrown when a caller-pinned function is invoked by any other caller.
    error IYieldRepurchaseFacilityV2_InvalidCaller();

    /// @notice Thrown when a redeem returns less reserve than its preview.
    /// @param vault The vault that was redeemed from.
    /// @param expected The reserve amount previewed.
    /// @param received The reserve amount received.
    error IYieldRepurchaseFacilityV2_InsufficientRedeem(
        address vault,
        uint256 expected,
        uint256 received
    );

    /// @notice Thrown when the reserve token decimals exceed the supported maximum of 18.
    error IYieldRepurchaseFacilityV2_UnsupportedDecimals();

    /// @notice Thrown when the PRICE module does not report the 18 decimals of the
    ///         backing value.
    error IYieldRepurchaseFacilityV2_UnsupportedOracleDecimals();

    /// @notice Thrown when `seedCycle` is invoked after the one-shot seeding has been
    ///         consumed.
    error IYieldRepurchaseFacilityV2_CycleAlreadySeeded();

    /// @notice Thrown when `seedCycle` is invoked while the epoch counter does not hold
    ///         the restart value of 20 that `enable` sets.
    error IYieldRepurchaseFacilityV2_CycleAlreadyStarted();

    /// @notice Thrown when the seeded epoch is not below the weekly epoch count of 21.
    error IYieldRepurchaseFacilityV2_EpochSeedTooHigh();

    // ============ STRUCTS ============ //

    /// @notice The configuration and accounting of a registered reserve asset.
    /// @param vault The ERC4626 vault.
    /// @param reserve The vault's underlying reserve token.
    /// @param reserveDecimals The reserve token decimals, equal to the vault share decimals.
    /// @param sellShares Whether bond markets pay out the vault shares instead of the reserve.
    /// @param isAssetEnabled Whether the asset participates in the weekly and daily cycles.
    /// @param yieldBuybackShare The share of the projected yield routed to buybacks
    ///        (`1e18` = 100%).
    /// @param lastReserveBalance The protocol reserve balance snapshot of the last weekly reset,
    ///        in reserve units.
    /// @param lastConversionRate The reserve amount redeemable for one whole share at the last
    ///        weekly reset.
    /// @param nextYield The yield injected into the weekly budget at the next weekly reset,
    ///        in reserve units.
    /// @param weeklyBudgetRemaining The unspent buyback budget of the running week, in reserve
    ///        units.
    /// @param prefundedShares The vault shares held by the facility and tracked by the budget
    ///        accounting.
    /// @param prefundedReserve The reserve held by the facility and tracked by the budget
    ///        accounting.
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

    /// @notice A per-vault seed of the stored next yield, supplied in the `enable`
    ///         payload.
    /// @dev The `enable` payload is `abi.encode(uint256 initialDiscount, NextYieldSeed[]
    ///      seeds)`. The restart performed by `enable` zeroes the next yields of all
    ///      enabled vaults first, and each seed then sets the next yield of an enabled
    ///      registered vault; when the array contains duplicates, the last entry wins. An
    ///      empty array performs a plain full restart with zero yields. Disabled vaults
    ///      are not seedable.
    /// @param vault The registered vault to seed.
    /// @param nextYield The seeded next yield, in reserve units.
    struct NextYieldSeed {
        address vault;
        uint256 nextYield;
    }

    /// @notice A per-vault seed of the running week's buyback budget, supplied to
    ///         `seedCycle`.
    /// @dev The seeded amount is added to the vault's `weeklyBudgetRemaining` (see
    ///      `getAssetConfig`) and covered by a withdrawal of vault shares from the
    ///      treasury; when the array contains duplicates, their amounts accumulate.
    /// @param vault The registered vault to seed; its asset must be enabled.
    /// @param weeklyBudget The amount added to the running week's budget, in reserve
    ///        units; must be non-zero.
    struct WeeklyBudgetSeed {
        address vault;
        uint256 weeklyBudget;
    }

    // ============ FUNCTIONS ============ //

    /// @notice Registers an ERC4626 vault as a reserve asset, optionally seeding its next
    ///         yield and designating it as the backing vault.
    /// @dev Callable by the admin role. The asset is registered in the enabled state. The
    ///      vault's share decimals must equal its reserve decimals, the reserve decimals
    ///      must not exceed 18, and only one vault per reserve token can be registered.
    ///      A sell-shares vault cannot be designated as the backing vault.
    ///
    ///      The snapshot parameters are the baseline of the first yield projection, and
    ///      `nextYield_` is injected into the weekly budget at the first weekly reset.
    ///      Emits `AssetAdded` and `NextYieldSet`, and `BackingVaultSet` when
    ///      `setAsBackingVault_` is set.
    /// @param vault_ The ERC4626 vault to register.
    /// @param yieldBuybackShare_ The share of the yield routed to buybacks (`1e18` = 100%).
    /// @param initialReserveBalance_ The initial `lastReserveBalance` snapshot, in reserve
    ///        units.
    /// @param initialConversionRate_ The initial `lastConversionRate` snapshot: the
    ///        reserve amount redeemable for one whole share.
    /// @param nextYield_ The initial stored next yield, in reserve units.
    /// @param sellShares_ Whether bond markets pay out the vault shares instead of the
    ///        reserve.
    /// @param setAsBackingVault_ Whether the vault becomes the backing vault.
    function addAsset(
        address vault_,
        uint256 yieldBuybackShare_,
        uint256 initialReserveBalance_,
        uint256 initialConversionRate_,
        uint256 nextYield_,
        bool sellShares_,
        bool setAsBackingVault_
    ) external;

    /// @notice Seeds the weekly cycle: sets the epoch counter to the supplied value,
    ///         adds each seeded amount to its vault's weekly buyback budget, and covers
    ///         the budgets with treasury withdrawals.
    /// @dev Callable by the admin role, at most once over the lifetime of the contract,
    ///      only while the facility is enabled, and only while the epoch counter holds
    ///      the restart value of 20 that `enable` sets, so a heart beat between the
    ///      restart and the seeding is rejected. The expected call order is `enable`
    ///      first, then `addAsset` for every seeded vault, then this function: the
    ///      restart performed by `enable` refreshes the snapshots and zeroes the next
    ///      yields of the enabled assets that are already registered, erasing their
    ///      `addAsset` seeds.
    ///
    ///      The seeded budgets fund the daily market cycles remaining in the week (an
    ///      epoch of 18 or later leaves none), and the unspent remainder is retained by
    ///      the following weekly reset. The stored next yields and the yield snapshots
    ///      are not affected. An empty seed array seeds only the epoch and emits no
    ///      event. Emits `WeeklyBudgetSeeded` per seed.
    /// @param epoch_ The epoch counter to resume at, in the range `[0, 21)`.
    /// @param budgetSeeds_ The per-vault budget seeds; every seeded vault must be
    ///        registered with an enabled asset, and every seeded amount must be
    ///        non-zero.
    function seedCycle(uint48 epoch_, WeeklyBudgetSeed[] calldata budgetSeeds_) external;

    /// @notice De-registers a disabled vault, transferring the facility's balances of the
    ///         vault shares and its reserve to the treasury and deleting the per-vault
    ///         configuration and accounting.
    /// @dev Callable by the admin role. The vault must be disabled and must not be the
    ///      backing vault. Emits `AssetRemoved`.
    /// @param vault_ The vault to de-register.
    function removeAsset(address vault_) external;

    /// @notice Sets the backing oracle consulted for the market price floor gate and for
    ///         pricing the burn of the purchased OHM.
    /// @dev Callable by the admin role. The oracle must report the backing as an
    ///      18-decimal reserve-per-OHM value. Emits `BackingOracleSet`.
    /// @param backingOracle_ The backing oracle policy; must not be the zero address.
    function setBackingOracle(address backingOracle_) external;

    /// @notice Designates a registered vault as the backing vault: its yield projection
    ///         includes the Clearinghouse interest, its protocol balance includes the
    ///         active Clearinghouses, and the purchased OHM is burned against
    ///         withdrawals from it.
    /// @dev Callable by the admin role. The vault must be registered, enabled, and not
    ///      sell-shares. The backing vault cannot be disabled or removed while
    ///      designated, and the designation can only be replaced, not cleared. Emits
    ///      `BackingVaultSet`.
    /// @param vault_ The vault to designate.
    function setBackingVault(address vault_) external;

    /// @notice Sets the SDA auctioneer used to create bond markets and the teller trusted
    ///         to invoke the bond callback.
    /// @dev Callable by the admin role. Both addresses must be non-zero. Market creation
    ///      requires the facility to be callback-authorized on the auctioneer; a market
    ///      submission the auctioneer rejects is skipped with `MarketCreationFailed`.
    ///      Emits `BondContractsSet`.
    /// @param bondAuctioneer_ The SDA auctioneer.
    /// @param teller_ The teller.
    function setBondContracts(address bondAuctioneer_, address teller_) external;

    /// @notice Sets the cumulative receivables offset of a Clearinghouse. The offset is
    ///         subtracted from the Clearinghouse's `principalReceivables` when the weekly
    ///         reset projects the yield, neutralizing receivables that do not accrue
    ///         interest to the treasury.
    /// @dev Callable by the admin role. The offset is validated against the current
    ///      `principalReceivables` and may be set in both directions. Emits
    ///      `ClearinghouseOffsetSet`.
    /// @param clearinghouse_ The Clearinghouse address; must not be the zero address.
    /// @param offset_ The new cumulative offset, in the receivables' units.
    function setClearinghouseOffset(address clearinghouse_, uint256 offset_) external;

    /// @notice Sets the yield buyback share of a registered vault.
    /// @dev Callable by the YRF timelock and the admin role. The share multiplies the
    ///      yield projected at the weekly reset; the stored next yield is not affected.
    ///      Emits `YieldBuybackShareSet`.
    /// @param vault_ The registered vault.
    /// @param newShare_ The new share (`1e18` = 100%); must not exceed `1e18`.
    function setYieldBuybackShare(address vault_, uint256 newShare_) external;

    /// @notice Sets the discount applied to the oracle price when a bond market opens:
    ///         the market's initial price corresponds to the oracle price reduced by the
    ///         discount, while its minimum price corresponds to the undiscounted oracle
    ///         price.
    /// @dev Callable by the YRF timelock and the admin role. Emits `InitialDiscountSet`.
    /// @param initialDiscount_ The new discount (`1e18` = 100%); must be less than `1e18`.
    function setInitialDiscount(uint256 initialDiscount_) external;

    /// @notice Increases the cumulative receivables offset of a Clearinghouse.
    /// @dev Callable by the YRF timelock and the admin role. The resulting offset is
    ///      validated against the current `principalReceivables`. This path can only
    ///      increase the offset, which reduces the projected yield; lowering the offset
    ///      requires the admin role, via `setClearinghouseOffset`. Emits
    ///      `ClearinghouseOffsetSet`.
    /// @param clearinghouse_ The Clearinghouse address; must not be the zero address.
    /// @param additionalOffset_ The amount added to the existing offset, in the
    ///        receivables' units.
    function increaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external;

    /// @notice Lowers the stored next yield of a registered vault, correcting a
    ///         projection that overstates the yield before the next weekly reset injects
    ///         it into the budget.
    /// @dev Callable by the YRF timelock and the admin role. The expected current value
    ///      guards against a weekly reset replacing the stored value between the
    ///      correction being prepared and applied: on a mismatch the correction reverts
    ///      instead of cutting the fresh projection. Emits `NextYieldSet`.
    /// @param vault_ The registered vault.
    /// @param expectedNextYield_ The stored next yield the correction targets, in reserve
    ///        units.
    /// @param newNextYield_ The corrected next yield, in reserve units; must be lower
    ///        than the stored value.
    function decreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external;

    /// @notice Includes a Clearinghouse in the backing vault's yield projection
    ///         regardless of its reserve token.
    /// @dev Callable by the admin role. By default only Clearinghouses whose reserve
    ///      matches the backing reserve are counted; inclusion is meant for
    ///      Clearinghouses whose receivables accrue to the backing reserve, so the
    ///      receivables must be denominated in a token with the same decimals as the
    ///      backing reserve. The receivables offset of the Clearinghouse applies as
    ///      usual, and `ClearinghouseDebtTokenMismatch` is not emitted for an included
    ///      Clearinghouse. Only Clearinghouses present in the CHREG registry are
    ///      iterated, so including any other address has no effect. Emits
    ///      `ClearinghouseIncluded`.
    /// @param clearinghouse_ The Clearinghouse address; must not be the zero address and
    ///        must not be included already.
    function includeClearinghouse(address clearinghouse_) external;

    /// @notice Removes a Clearinghouse from the backing vault's yield projection,
    ///         restoring the default reserve-token filter for it.
    /// @dev Callable by the YRF timelock and the admin role. Emits
    ///      `ClearinghouseExcluded`.
    /// @param clearinghouse_ The included Clearinghouse address.
    function excludeClearinghouse(address clearinghouse_) external;

    /// @notice Enables a disabled registered vault. The stored next yield is reset to
    ///         zero and the yield snapshots are refreshed, so the yield projection
    ///         resumes at the following weekly reset.
    /// @dev Callable by the YRF timelock and the admin role. Emits `AssetEnabled` and
    ///      `NextYieldSet`.
    /// @param vault_ The vault to enable.
    function enableAsset(address vault_) external;

    /// @notice Disables an enabled registered vault. A disabled vault is skipped by the
    ///         weekly and daily cycles, and purchases on its open bond markets revert;
    ///         its budget and holdings stay in place.
    /// @dev Callable by the YRF timelock and the admin role. The backing vault cannot be
    ///      disabled. Emits `AssetDisabled`.
    /// @param vault_ The vault to disable.
    function disableAsset(address vault_) external;

    /// @notice Burns the purchased OHM held by the facility, transfers all remaining OHM,
    ///         vault, and reserve balances to the treasury, and zeroes the per-vault
    ///         holdings accounting and weekly budgets.
    /// @dev Callable by the emergency and admin roles, and only while the facility is
    ///      disabled. The per-vault stored next yields are preserved, so a later
    ///      `reEnable` or `enable` refunds the facility from the treasury at the next
    ///      weekly reset. Each vault is swept independently: a vault whose sweep fails is
    ///      skipped with `FundsReturnSkipped`, keeping its balances and accounting, and
    ///      is retried by the next call. Emits `FundsReturnedToTreasury`.
    function returnFundsToTreasury() external;

    /// @notice Contributes funds to a vault's weekly buyback budget: the supplied amount
    ///         is added to the tracked holdings, and its redeemable value is credited to
    ///         the budget and spent over the remaining daily cycles of the running week.
    /// @dev Callable by anyone; a contribution is an irreversible donation drawn from the
    ///      caller. A reserve contribution is wrapped into vault shares through the
    ///      vault's `deposit`, so the caller must approve the facility for the reserve;
    ///      a share contribution requires an approval for the vault shares. The vault's
    ///      own deposit restrictions apply to the wrap. Emits `Contributed`.
    /// @param vault_ The registered vault to contribute to; its asset must be enabled.
    /// @param amount_ The contribution amount: vault shares when `inShares_` is set, and
    ///        reserve units otherwise.
    /// @param inShares_ Whether `amount_` is denominated in vault shares.
    function contribute(address vault_, uint256 amount_, bool inShares_) external;

    // ============ VIEW FUNCTIONS ============ //

    /// @notice Returns the registered vaults.
    /// @dev The ordering is not meaningful: removals reorder the list.
    /// @return vaults The registered vault addresses.
    function getVaults() external view returns (address[] memory);

    /// @notice Returns the configuration and accounting of a registered vault.
    /// @dev Reverts with `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an
    ///      unregistered vault.
    /// @param vault_ The registered vault.
    /// @return config The per-vault configuration and accounting.
    function getAssetConfig(address vault_) external view returns (ReserveAsset memory config);

    /// @notice Returns the yield a weekly reset running now would project for the vault:
    ///         the vault yield accrued since the snapshots, plus the weekly Clearinghouse
    ///         interest for the backing vault, multiplied by the vault's buyback share.
    /// @dev This is a live projection; the stored next yield is available through
    ///      `getAssetConfig`. Reverts with `IYieldRepurchaseFacilityV2_AssetNotRegistered`
    ///      for an unregistered vault.
    /// @param vault_ The registered vault.
    /// @return yield The projected yield, in reserve units.
    function getNextYield(address vault_) external view returns (uint256 yield);

    /// @notice Returns the reserve value of the protocol-held shares of a vault: the
    ///         treasury balance, and for the backing vault also the balances of the
    ///         active Clearinghouses.
    /// @dev Reverts with `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an
    ///      unregistered vault.
    /// @param vault_ The registered vault.
    /// @return balance The reserve value, in reserve units.
    function getReserveBalance(address vault_) external view returns (uint256 balance);

    /// @notice Returns the reserve token of the vault that funds a market created by the
    ///         facility.
    /// @param marketId_ The market ID.
    /// @return reserve The reserve token, or the zero address when the market was not
    ///         created by the facility.
    function marketReserves(uint256 marketId_) external view returns (address reserve);

    /// @notice Returns the cumulative receivables offset of a Clearinghouse.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @return The cumulative offset, in the receivables' units.
    function clearinghouseOffset(address clearinghouse_) external view returns (uint256);

    /// @notice Returns whether a Clearinghouse is included in the backing yield regardless
    ///         of its reserve token.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @return Whether the Clearinghouse is included.
    function isClearinghouseIncluded(address clearinghouse_) external view returns (bool);

    /// @notice Returns the teller trusted to invoke the bond callback.
    /// @return The teller address.
    function teller() external view returns (address);

    /// @notice Returns the SDA auctioneer used to create bond markets.
    /// @return The auctioneer address.
    function bondAuctioneer() external view returns (address);

    /// @notice Returns the backing oracle providing the 18-decimal reserve-per-OHM
    ///         backing value.
    /// @return The backing oracle policy address.
    function backingOracle() external view returns (address);

    /// @notice Returns the backing vault.
    /// @return The backing vault address, or the zero address when none is designated.
    function backingVault() external view returns (address);

    /// @notice Returns the discount applied to the oracle price when a bond market opens.
    /// @return The discount (`1e18` = 100%).
    function initialDiscount() external view returns (uint256);

    /// @notice Returns the OHM purchased through the facility's bond markets and not yet
    ///         burned.
    /// @dev The facility's OHM balance always covers this amount.
    /// @return The purchased OHM amount.
    function ohmPurchased() external view returns (uint256);

    /// @notice Returns the running epoch counter, in the range `[0, 21)`.
    /// @dev The counter advances by one per heart beat while the facility is enabled;
    ///      three epochs form a day, and reaching epoch 21 runs the weekly reset before
    ///      the counter wraps to zero. A restart through `enable` sets the counter to
    ///      20, and `seedCycle` sets it to the seeded value.
    /// @return The epoch counter.
    function epoch() external view returns (uint48);

    /// @notice Returns whether the one-shot `seedCycle` has been consumed.
    /// @return Whether the cycle has been seeded.
    function isCycleSeeded() external view returns (bool);

    /// @notice Returns the address of the YRF timelock policy authorized to call the
    ///         timelocked operational functions.
    /// @return The YRF timelock address.
    function timelock() external view returns (address);

    /// @notice Returns the exclusive upper bound of the re-enable grace window, in
    ///         seconds: the window must be strictly shorter than one weekly cycle.
    /// @return The bound, in seconds.
    // solhint-disable-next-line func-name-mixedcase
    function MAX_GRACE_PERIOD() external view returns (uint32);
}
