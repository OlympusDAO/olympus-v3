// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Interfaces
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

/// @title IYieldRepurchaseFacilityV2Write
/// @notice The state-changing surface of the multi-asset Yield Repurchase Facility (YRF)
///         policy.
/// @dev Role restrictions are stated per function. Functions restricted to the
///      configurator are callable only by the configuration policy returned by
///      `configurator()`, and revert while `execute`, `callback`, or `seedCycle` is
///      executing. The facility also implements: `IPeriodicTask.execute`,
///      restricted to the heart role; `IBondCallback.callback`, restricted to the
///      configured teller; `IEnabler.enable`, restricted to the admin role, and
///      `IEnabler.disable`, restricted to the emergency and admin roles;
///      `IReEnabler.reEnable`, restricted to the yrf_admin role within the grace window
///      after a disable; and `IBasicRescueable.rescue`, restricted to the yrf_admin and
///      admin roles.
interface IYieldRepurchaseFacilityV2Write {
    /// @notice Registers an ERC4626 vault as a reserve asset, optionally seeding its next
    ///         yield and designating it as the backing vault.
    /// @dev Callable by the configurator. The asset is registered in the enabled state. The
    ///      vault's share decimals must equal its reserve decimals, the reserve decimals
    ///      must not exceed 18, the reserve must resolve to a non-zero OHM price through
    ///      the PRICE module, and a sell-shares vault cannot be designated as the backing
    ///      vault. The designation is only available while no backing vault is
    ///      designated; replacing an existing designation requires `setBackingVault`.
    ///
    ///      Every token balance held by the facility belongs to exactly one pool, so the
    ///      registration rejects any token collision: neither the vault nor the reserve
    ///      may be OHM, the vault may not equal its own reserve, and neither may equal
    ///      the vault or the reserve of a registered asset.
    ///
    ///      The snapshot parameters are the baseline of the first yield projection, and
    ///      `nextYield_` is withdrawn into the buyback pool at the first weekly reset.
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

    /// @notice Seeds the weekly cycle: sets the epoch counter to the supplied value and
    ///         withdraws each seeded amount from the treasury into its vault's buyback
    ///         pool.
    /// @dev Callable by the admin role, at most once per `enable` restart, only while
    ///      the facility is enabled, and only before the first heart beat of the
    ///      restart: every `enable` opens the seeding window (see `isCycleSeedable`),
    ///      and the seeding or the first beat closes it. The expected call order is
    ///      `enable` first, then `addAsset` for every seeded vault, then this function:
    ///      the restart performed by `enable` refreshes the snapshots and zeroes the
    ///      next yields of the enabled assets that are already registered, erasing their
    ///      `addAsset` seeds.
    ///
    ///      The seeded pools fund the daily market cycles remaining in the week (an
    ///      epoch of 18 or later leaves none), and the unspent remainder stays in the
    ///      pool across the following weekly reset. The stored next yields and the yield
    ///      snapshots are not affected. An empty seed array seeds only the epoch and
    ///      emits no event; the seeding stays observable through `isCycleSeedable` and
    ///      `epoch`. A treasury balance that does not cover a seeded amount is reported
    ///      with `PrefundShortfall`, and the unfunded remainder is carried (see
    ///      `ReserveAsset.unfundedYield`) and retried at the next weekly reset. Emits
    ///      `WeeklyBudgetSeeded` per seed.
    /// @param epoch_ The epoch counter to resume at, in the range `[0, 21)`.
    /// @param budgetSeeds_ The per-vault pool seeds; every seeded vault must be
    ///        registered with an enabled asset, and every seeded amount must be
    ///        non-zero.
    function seedCycle(
        uint48 epoch_,
        IYieldRepurchaseFacilityV2.WeeklyBudgetSeed[] calldata budgetSeeds_
    ) external;

    /// @notice De-registers a disabled vault, closing its live bond market on a
    ///         best-effort basis, transferring the facility's balances of the vault
    ///         shares and its reserve to the treasury, and deleting the per-vault
    ///         configuration and accounting.
    /// @dev Callable by the configurator. The vault must be disabled and must not be the
    ///      backing vault. Emits `AssetRemoved`.
    /// @param vault_ The vault to de-register.
    function removeAsset(address vault_) external;

    /// @notice Sets the backing oracle consulted for the market price floor gate and for
    ///         pricing the burn of the purchased OHM.
    /// @dev Callable by the admin role. The oracle must be an active policy of the
    ///      facility's kernel and report the backing as an 18-decimal reserve-per-OHM
    ///      value: an oracle whose `decimals()` is not 18 is rejected. Emits
    ///      `BackingOracleSet`.
    /// @param backingOracle_ The backing oracle policy; must not be the zero address.
    function setBackingOracle(address backingOracle_) external;

    /// @notice Sets the configurator: the configuration policy that is the only caller of
    ///         the configurator-restricted functions.
    /// @dev Callable by the admin role, only while the facility is disabled. The
    ///      configurator must be an active policy of the facility's kernel, advertise
    ///      `IYieldRepurchaseFacilityV2Config` through ERC165, and report this facility as
    ///      its `facility()`. `enable` and `reEnable` check the same conditions. Emits
    ///      `ConfiguratorSet`.
    /// @param configurator_ The configuration policy.
    function setConfigurator(address configurator_) external;

    /// @notice Sets whether the vault's bond markets pay out the vault shares instead of
    ///         the reserve.
    /// @dev Callable by the configurator. The backing vault cannot sell shares. The
    ///      vault's tracked live bond market is closed before the change, and a failing
    ///      close reverts the change. The per-vault accounting is denominated in
    ///      reserve units in both modes and is not affected; the held balances are
    ///      spent by the following daily cycles under the new mode. The reserve mode
    ///      requires a redeemable vault: with `sellShares_` unset the daily cycles
    ///      redeem the held shares for the bids, so on a vault whose redeem reverts the
    ///      redeem is skipped with `RedeemFailed`, the bid is clamped to the held
    ///      reserve balance, and a zero bid opens no market. Emits `SellSharesSet`.
    /// @param vault_ The registered vault.
    /// @param sellShares_ Whether bond markets pay out the vault shares; must differ
    ///        from the stored mode.
    function setSellShares(address vault_, bool sellShares_) external;

    /// @notice Designates a registered vault as the backing vault: its yield projection
    ///         includes the Clearinghouse interest, its protocol balance includes the
    ///         active Clearinghouses, and the purchased OHM is burned against
    ///         withdrawals from it.
    /// @dev Callable by the configurator. The vault must be registered, enabled, and not
    ///      sell-shares. The backing vault cannot be disabled or removed while
    ///      designated, and the designation can only be replaced, not cleared. Emits
    ///      `BackingVaultSet`.
    /// @param vault_ The vault to designate.
    function setBackingVault(address vault_) external;

    /// @notice Sets the SDA auctioneer used to create bond markets; the teller trusted to
    ///         invoke the bond callback is resolved from the auctioneer's `getTeller()`,
    ///         so the pair stays consistent.
    /// @dev Callable by the admin role. The auctioneer and its reported teller must be
    ///      non-zero. The live bond markets are closed on the outgoing auctioneer before
    ///      the change, on a best-effort basis: a revert of the auctioneer is absorbed
    ///      and the affected market is left to expire, unpurchasable. The facility must
    ///      be authorized as a market callback on the auctioneer: `enable` and a
    ///      reconfiguration of the enabled facility revert without the authorization,
    ///      while a revocation after the fact degrades to market submissions the
    ///      auctioneer rejects, skipped with `MarketCreationFailed`. Emits
    ///      `BondContractsSet`.
    /// @param bondAuctioneer_ The SDA auctioneer.
    function setBondContracts(address bondAuctioneer_) external;

    /// @notice Sets the cumulative receivables offset of a Clearinghouse. The offset is
    ///         subtracted from the Clearinghouse's `principalReceivables` when the weekly
    ///         reset projects the yield, neutralizing receivables that do not accrue
    ///         interest to the treasury.
    /// @dev Callable by the configurator. The offset is validated against the current
    ///      `principalReceivables` and may be set in both directions. Emits
    ///      `ClearinghouseOffsetSet`.
    /// @param clearinghouse_ The Clearinghouse address; must not be the zero address.
    /// @param offset_ The new cumulative offset, in the receivables' units.
    function setClearinghouseOffset(address clearinghouse_, uint256 offset_) external;

    /// @notice Sets the yield buyback share of a registered vault.
    /// @dev Callable by the configurator. The share multiplies the yield projected at the
    ///      weekly reset; the stored next yield is not affected. Emits
    ///      `YieldBuybackShareSet`.
    /// @param vault_ The registered vault.
    /// @param newShare_ The new share (`1e18` = 100%); must not exceed `1e18`.
    function setYieldBuybackShare(address vault_, uint256 newShare_) external;

    /// @notice Sets the discount applied to the oracle price when a bond market opens:
    ///         the market's initial price corresponds to the oracle price reduced by the
    ///         discount.
    /// @dev Callable by the configurator. Emits `InitialDiscountSet`.
    /// @param initialDiscount_ The new discount (`1e18` = 100%); must be less than `1e18`.
    function setInitialDiscount(uint256 initialDiscount_) external;

    /// @notice Sets the premium over the oracle price at which a bond market's minimum
    ///         price is placed: the market decays from its initial price down to that
    ///         minimum, so the premium caps the reserve paid for one OHM at
    ///         `oraclePrice * (1 + maxPricePremium)`.
    /// @dev Callable by the configurator. Emits `MaxPricePremiumSet`.
    ///
    ///      The premium is measured from the oracle price and is therefore independent
    ///      of the initial discount: the discount sets where a market opens, and the
    ///      premium sets the ceiling it may decay to. A zero premium caps the payout at
    ///      the oracle price, leaving a market only the discount as decay room.
    ///
    ///      Together the two parameters set the width of the decay band,
    ///      `(1 + maxPricePremium) / (1 - initialDiscount)`. A band too narrow leaves a
    ///      market unable to reach a clearing price when the OHM price rises after the
    ///      market opens, which strands that day's capacity in the buyback pool; a
    ///      premium too large raises the price the facility can pay for one OHM.
    /// @param maxPricePremium_ The new premium (`1e18` = 100%); must not exceed
    ///        `10e18`.
    function setMaxPricePremium(uint256 maxPricePremium_) external;

    /// @notice Increases the cumulative receivables offset of a Clearinghouse.
    /// @dev Callable by the configurator. The resulting offset is validated against the
    ///      current `principalReceivables`. This path can only increase the offset, which
    ///      reduces the projected yield; the offset is lowered through
    ///      `setClearinghouseOffset`. Emits
    ///      `ClearinghouseOffsetSet`.
    /// @param clearinghouse_ The Clearinghouse address; must not be the zero address.
    /// @param additionalOffset_ The amount added to the existing offset, in the
    ///        receivables' units.
    function increaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external;

    /// @notice Lowers the stored next yield of a registered vault, correcting a
    ///         projection that overstates the yield before the next weekly reset
    ///         withdraws it into the buyback pool.
    /// @dev Callable by the configurator. The expected current value
    ///      guards against a weekly reset replacing the stored value between the
    ///      correction being prepared and applied: on a mismatch the correction reverts
    ///      instead of cutting the fresh projection. The function lowers only the stored
    ///      projection; the `unfundedYield` carry is corrected only through an `enable`
    ///      restart. Emits `NextYieldSet`.
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
    /// @dev Callable by the configurator. By default only Clearinghouses whose reserve
    ///      matches the backing reserve are counted; inclusion is meant for
    ///      Clearinghouses whose receivables accrue to the backing reserve, so the
    ///      receivables must be denominated in a token with the same decimals as the
    ///      backing reserve. A Clearinghouse whose `reserve()` read reverts (for
    ///      example when the function is not exposed) never matches the backing
    ///      reserve, so it is counted only while included. The receivables offset of
    ///      the Clearinghouse applies as usual, and `ClearinghouseDebtTokenMismatch`
    ///      is not emitted for an included Clearinghouse. The address must be present
    ///      in the CHREG registry and its `principalReceivables()` must be readable (a
    ///      zero value is valid). Emits `ClearinghouseIncluded`.
    /// @param clearinghouse_ The Clearinghouse address; must not be included already.
    function includeClearinghouse(address clearinghouse_) external;

    /// @notice Removes a Clearinghouse from the backing vault's yield projection,
    ///         restoring the default reserve-token filter for it.
    /// @dev Callable by the configurator. Emits `ClearinghouseExcluded`.
    /// @param clearinghouse_ The included Clearinghouse address.
    function excludeClearinghouse(address clearinghouse_) external;

    /// @notice Enables a disabled registered vault. The stored next yield and the
    ///         unfunded carry are reset to zero and the yield snapshots are refreshed,
    ///         so the yield projection resumes at the following weekly reset.
    /// @dev Callable by the configurator. Emits `AssetEnabled` and `NextYieldSet`.
    /// @param vault_ The vault to enable.
    function enableAsset(address vault_) external;

    /// @notice Disables an enabled registered vault. A disabled vault is skipped by the
    ///         weekly and daily cycles, its live bond market is closed on a best-effort
    ///         basis (a revert of the auctioneer leaves the market to expire), and
    ///         purchases on any remaining market of the vault revert; its buyback pool
    ///         and accounting stay in place.
    /// @dev Callable by the configurator. The backing vault cannot be disabled. Emits
    ///      `AssetDisabled`.
    /// @param vault_ The vault to disable.
    function disableAsset(address vault_) external;

    /// @notice Burns the purchased OHM held by the facility and transfers all remaining
    ///         OHM, vault, and reserve balances to the treasury, emptying the buyback
    ///         pools.
    /// @dev Callable by the emergency and admin roles, and only while the facility is
    ///      disabled. The per-vault stored next yields and unfunded carries are
    ///      preserved, so a later `reEnable` or `enable` refunds the facility from the
    ///      treasury at the next weekly reset. Each vault is swept independently: a vault
    ///      whose sweep fails is skipped with `FundsReturnSkipped`, keeping its balances,
    ///      and is retried by the next call. Emits `FundsReturnedToTreasury`.
    function returnFundsToTreasury() external;
}
