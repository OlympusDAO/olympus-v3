// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IYieldRepurchaseFacilityV2
/// @notice The events, errors, and data types of the multi-asset Yield Repurchase
///         Facility (YRF) policy. The facility draws yield from registered ERC4626
///         reserve vaults held by the treasury, spends it through daily Bond Protocol
///         markets that buy OHM, and burns the purchased OHM against a treasury
///         withdrawal priced by the backing oracle.
/// @dev Amount conventions: reserve amounts are denominated in the reserve token's
///      decimals, vault share amounts in the vault's decimals (equal to the reserve
///      decimals for every registered vault), and OHM amounts in the OHM decimals.
///      Percentage parameters are scaled by `1e18` (`1e18` = 100%). The oracle price of
///      an asset is the OHM price denominated in its reserve token, resolved live
///      through the PRICE module per daily cycle; the oracle prices and the backing
///      value are 18-decimal reserve-per-OHM quotes.
///
///      The reserve-side accounting is balance-based: the facility's holdings of a
///      vault's shares and of its reserve token form the vault's buyback pool, and the
///      daily markets are sized from those balances. A plain transfer of the vault
///      shares or of the reserve token to the facility is an irreversible donation that
///      joins the pool and is spent by the following daily cycles at prices no lower
///      than the market floor. Donations never increase treasury withdrawals: the
///      treasury is drawn only for the stored yield projection at the weekly reset, for
///      the backing of purchased-and-burned OHM, and for the admin-supplied seeds, and
///      none of those paths reads the facility's balances. The OHM channel is exempt
///      from the balance-based convention: purchased OHM is tracked by a counter and
///      donated OHM is never burned against a treasury withdrawal.
interface IYieldRepurchaseFacilityV2 {
    // ============ EVENTS ============ //

    /// @notice Emitted when a bond market is created for a vault.
    /// @param vault The vault whose buyback pool funds the market.
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

    /// @notice Emitted when the configurator is set.
    /// @param configurator The configuration policy.
    event ConfiguratorSet(address indexed configurator);

    /// @notice Emitted when the backing vault is set.
    /// @param backingVault The vault designated as the backing vault.
    event BackingVaultSet(address indexed backingVault);

    /// @notice Emitted when the sell-shares mode of a vault is set.
    /// @param vault The vault whose mode is set.
    /// @param sellShares Whether bond markets pay out the vault shares instead of the
    ///        reserve.
    event SellSharesSet(address indexed vault, bool sellShares);

    /// @notice Emitted when the bond auctioneer and the teller are set.
    /// @param bondAuctioneer The SDA auctioneer used to create markets.
    /// @param bondTeller The teller trusted to invoke the bond callback.
    event BondContractsSet(address indexed bondAuctioneer, address indexed bondTeller);

    /// @notice Emitted when the initial bond market discount is set.
    /// @param initialDiscount The new discount (`1e18` = 100%).
    event InitialDiscountSet(uint256 initialDiscount);

    /// @notice Emitted when the bond market max price premium is set.
    /// @param maxPricePremium The new premium (`1e18` = 100%).
    event MaxPricePremiumSet(uint256 maxPricePremium);

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
    /// @param reason The raw revert data of the failed redeem, truncated to at most 256
    ///        bytes.
    event RedeemFailed(address indexed vault, uint256 shares, bytes reason);

    /// @notice Emitted when a market creation is rejected; the funds stay with the
    ///         facility and the day's market for the vault is skipped.
    /// @param vault The vault whose market was not created.
    /// @param bidAmount The intended market capacity, in payout token units.
    /// @param reason The raw revert data of the rejected submission, truncated to at
    ///        most 256 bytes; empty when the pricing was skipped before the submission
    ///        (a zero conversion rate).
    event MarketCreationFailed(address indexed vault, uint256 bidAmount, bytes reason);

    /// @notice Emitted when the best-effort close of a vault's tracked bond market
    ///         reverts; the market is left to expire on its own.
    /// @param vault The vault whose market close failed.
    /// @param marketId The market that was to be closed.
    /// @param reason The raw revert data of the failed close, truncated to at most 256
    ///        bytes.
    event MarketCloseFailed(address indexed vault, uint256 marketId, bytes reason);

    /// @notice Emitted when the treasury balance does not cover a sanctioned funding
    ///         withdrawal and the withdrawal is capped at the balance; the unfunded
    ///         remainder is carried and retried at the following weekly reset.
    /// @param vault The vault being funded.
    /// @param sharesRequested The share amount required to cover the funding target.
    /// @param sharesWithdrawn The share amount actually withdrawn.
    event PrefundShortfall(address indexed vault, uint256 sharesRequested, uint256 sharesWithdrawn);

    /// @notice Emitted when purchased OHM is burned against a backing withdrawal; the
    ///         withdrawn backing vault shares join the backing vault's buyback pool.
    /// @param ohmBurned The amount of OHM burned.
    /// @param backingWithdrawn The value of the withdrawn shares, in backing reserve
    ///        units.
    event OhmPurchasesProcessed(uint256 ohmBurned, uint256 backingWithdrawn);

    /// @notice Emitted when the funds held by the facility are returned to the treasury.
    /// @param ohmBurned The amount of purchased OHM that was burned.
    event FundsReturnedToTreasury(uint256 ohmBurned);

    /// @notice Emitted when the sweep of a vault by `returnFundsToTreasury` reverts and
    ///         is skipped; the vault's balances and accounting stay in place and are
    ///         retried by the next call.
    /// @param vault The vault whose sweep was skipped.
    /// @param reason The raw revert data of the failed sweep, truncated to at most 256
    ///        bytes.
    event FundsReturnSkipped(address indexed vault, bytes reason);

    /// @notice Emitted when the weekly reset of a vault reverts and is skipped; the vault
    ///         is retried at the following weekly reset.
    /// @param vault The vault whose reset was skipped.
    /// @param reason The raw revert data of the failed reset, truncated to at most 256
    ///        bytes.
    event WeeklyResetSkipped(address indexed vault, bytes reason);

    /// @notice Emitted when the daily cycle of a vault reverts and is skipped.
    /// @param vault The vault whose daily cycle was skipped.
    /// @param reason The raw revert data of the failed cycle, truncated to at most 256
    ///        bytes.
    event DailyCycleSkipped(address indexed vault, bytes reason);

    /// @notice Emitted when the processing of the purchased OHM reverts and is skipped;
    ///         the accumulated OHM is retried on the following beats.
    /// @param reason The raw revert data of the failed processing, truncated to at most
    ///        256 bytes.
    event OhmPurchasesProcessingSkipped(bytes reason);

    /// @notice Emitted when the wrap of a sell-shares vault's idle reserve balance into
    ///         vault shares reverts and is skipped; the reserve stays with the facility
    ///         and the wrap is retried at the following daily cycle.
    /// @param vault The vault whose reserve wrap was skipped.
    /// @param amount The reserve amount that was to be wrapped.
    /// @param reason The raw revert data of the failed wrap, truncated to at most 256
    ///        bytes.
    event ReserveWrapFailed(address indexed vault, uint256 amount, bytes reason);

    /// @notice Emitted when the running week's buyback pool of a vault is seeded by
    ///         `seedCycle`.
    /// @param vault The seeded vault.
    /// @param weeklyBudget The seeded amount, covered by a treasury withdrawal into the
    ///        vault's buyback pool, in reserve units.
    /// @param epoch The seeded epoch counter.
    event WeeklyBudgetSeeded(address indexed vault, uint256 weeklyBudget, uint48 epoch);

    // ============ ERRORS ============ //

    /// @notice Thrown when the `enable` payload is shorter than the minimum
    ///         `abi.encode(uint256 initialDiscount, uint256 maxPricePremium,
    ///         NextYieldSeed[] seeds)` encoding.
    error IYieldRepurchaseFacilityV2_InvalidEnableDataLength();

    /// @notice Thrown when a function targets a vault that is not registered.
    /// @param vault The unregistered vault.
    error IYieldRepurchaseFacilityV2_AssetNotRegistered(address vault);

    /// @notice Thrown when a token of the asset being registered already participates in
    ///         another balance pool: the token is OHM, the vault equals its own reserve,
    ///         or the vault or the reserve collides with the vault or the reserve of a
    ///         registered asset.
    /// @param token The conflicting token.
    error IYieldRepurchaseFacilityV2_TokenPoolConflict(address token);

    /// @notice Thrown when `rescue` targets the share or the reserve token of a
    ///         registered asset, whose balances form the asset's buyback pool.
    /// @param token The non-rescuable token.
    error IYieldRepurchaseFacilityV2_TokenNotRescuable(address token);

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

    /// @notice Thrown when `setSellShares` supplies the mode the vault already has.
    error IYieldRepurchaseFacilityV2_SellSharesUnchanged();

    /// @notice Thrown when a registration attempts to designate the backing vault while
    ///         one is already designated.
    error IYieldRepurchaseFacilityV2_BackingVaultAlreadySet();

    /// @notice Thrown when the vault's share decimals do not match its reserve decimals.
    error IYieldRepurchaseFacilityV2_VaultDecimalsMismatch();

    /// @notice Thrown when the reserve of the asset being registered resolves to a zero
    ///         OHM price through the PRICE module.
    /// @param reserve The reserve token that could not be priced.
    error IYieldRepurchaseFacilityV2_ReserveNotPriceable(address reserve);

    /// @notice Thrown when the initial discount is not less than 100% (`1e18`).
    error IYieldRepurchaseFacilityV2_InitialDiscountTooHigh();

    /// @notice Thrown when the max price premium is above 1,000% (`10e18`).
    error IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh();

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

    /// @notice Thrown when `includeClearinghouse` targets an address that is not present
    ///         in the CHREG registry.
    /// @param clearinghouse The address that is not a registered Clearinghouse.
    error IYieldRepurchaseFacilityV2_ClearinghouseNotInRegistry(address clearinghouse);

    /// @notice Thrown when `includeClearinghouse` targets a Clearinghouse whose
    ///         `principalReceivables()` read reverts.
    /// @param clearinghouse The Clearinghouse whose receivables could not be read.
    error IYieldRepurchaseFacilityV2_ClearinghouseReceivablesNotReadable(address clearinghouse);

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

    /// @notice Thrown when the bond callback targets a market that is not the tracked
    ///         live market of its vault.
    error IYieldRepurchaseFacilityV2_MarketNotCurrent();

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

    /// @notice Thrown when a vault deposit mints fewer shares than its preview.
    /// @param vault The vault that was deposited into.
    /// @param expected The share amount previewed.
    /// @param received The share amount received.
    error IYieldRepurchaseFacilityV2_InsufficientDeposit(
        address vault,
        uint256 expected,
        uint256 received
    );

    /// @notice Thrown when the reserve token decimals exceed the supported maximum of 18.
    error IYieldRepurchaseFacilityV2_UnsupportedDecimals();

    /// @notice Thrown when the PRICE module or the backing oracle does not report the 18
    ///         decimals of the backing value.
    error IYieldRepurchaseFacilityV2_UnsupportedOracleDecimals();

    /// @notice Thrown when the facility is not authorized as a market callback on the
    ///         bond auctioneer.
    error IYieldRepurchaseFacilityV2_CallbackNotAuthorized();

    /// @notice Thrown when `seedCycle` is invoked while its seeding window is closed:
    ///         the restart performed by `enable` has already been seeded, or a heart beat
    ///         has run since the restart.
    error IYieldRepurchaseFacilityV2_CycleNotSeedable();

    /// @notice Thrown when the seeded epoch is not below the weekly epoch count of 21.
    error IYieldRepurchaseFacilityV2_EpochSeedTooHigh();

    /// @notice Thrown when a configurator-restricted function is called by any other caller.
    /// @param caller The rejected caller.
    error IYieldRepurchaseFacilityV2_OnlyConfigurator(address caller);

    /// @notice Thrown when the configurator is unset, is not an active policy of the
    ///         facility's kernel, does not advertise `IYieldRepurchaseFacilityV2Config`, or
    ///         is not bound to the facility.
    /// @param configurator The rejected configurator address.
    error IYieldRepurchaseFacilityV2_InvalidConfigurator(address configurator);

    /// @notice Thrown when a proposed backing oracle does not report the facility's
    ///         kernel as its own or, on the admin setter path, is not an active policy
    ///         of the kernel.
    /// @param backingOracle The rejected backing oracle address.
    error IYieldRepurchaseFacilityV2_InvalidBackingOracle(address backingOracle);

    // ============ STRUCTS ============ //

    /// @notice The configuration and accounting of a registered reserve asset. The
    ///         facility's balances of the vault shares and of the reserve token are the
    ///         asset's buyback pool and are not mirrored by counters.
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
    /// @param nextYield The yield withdrawn from the treasury into the buyback pool at the next
    ///        weekly reset, in reserve units.
    /// @param unfundedYield The sanctioned yield the treasury balance could not cover, carried
    ///        into the funding target of the next weekly reset, in reserve units.
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
        uint256 unfundedYield;
    }

    /// @notice A per-vault seed of the stored next yield, supplied in the `enable`
    ///         payload.
    /// @dev The `enable` payload is `abi.encode(uint256 initialDiscount, uint256
    ///      maxPricePremium, NextYieldSeed[] seeds)`. The restart performed by `enable`
    ///      zeroes the next yields of all
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

    /// @notice A per-vault seed of the running week's buyback pool, supplied to
    ///         `seedCycle`.
    /// @dev The seeded amount is covered by a withdrawal of vault shares from the
    ///      treasury into the vault's buyback pool; when the array contains duplicates,
    ///      their amounts accumulate.
    /// @param vault The registered vault to seed; its asset must be enabled.
    /// @param weeklyBudget The amount withdrawn into the running week's buyback pool, in
    ///        reserve units; must be non-zero.
    struct WeeklyBudgetSeed {
        address vault;
        uint256 weeklyBudget;
    }
}
