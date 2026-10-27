// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IYieldRepurchaseFacilityV2Lens
/// @notice The derived read-only views of the multi-asset Yield Repurchase Facility
///         (YRF) policy: the live yield projection, the protocol reserve balance, the
///         buyback pools and the daily bid preview, the vault markets, the Clearinghouse
///         component of the backing yield, and the price gate.
/// @dev A lens holds no state: every view reads the raw getters of one facility, the
///      registered vaults, the treasury, the Clearinghouse registry, the PRICE module,
///      the backing oracle, and the bond auctioneer at the time of the call, and computes
///      through the formulas of the facility. A view reverts where the read it mirrors
///      reverts, for example `getNextYield` for an unregistered vault. Amount
///      conventions are those of `IYieldRepurchaseFacilityV2`.
interface IYieldRepurchaseFacilityV2Lens {
    // ============ STRUCTS ============ //

    /// @notice The buyback pool of a vault: the facility's balances of the vault's
    ///         shares and of its reserve token, and their value.
    /// @param heldShares The facility's balance of the share token, in share units.
    /// @param heldReserve The facility's balance of the reserve token, in reserve units.
    /// @param value The reserve value of the pool: the held reserve plus the value of
    ///        the held shares by the redemption class of the vault (floor), in reserve
    ///        units.
    struct BuybackPool {
        uint256 heldShares;
        uint256 heldReserve;
        uint256 value;
    }

    /// @notice The Clearinghouse component of the backing yield, per registry entry.
    /// @param clearinghouse The Clearinghouse address.
    /// @param counted Whether the Clearinghouse counts toward the backing yield: its
    ///        reserve matches the backing reserve, or it is included.
    /// @param receivables The Clearinghouse's `principalReceivables`, or zero when the
    ///        read reverts.
    /// @param offset The cumulative receivables offset stored by the facility.
    /// @param interest The weekly interest credited to the backing vault, in backing
    ///        reserve units; zero when the Clearinghouse is not counted.
    struct ClearinghouseYield {
        address clearinghouse;
        bool counted;
        uint256 receivables;
        uint256 offset;
        uint256 interest;
    }

    // ============ VIEW FUNCTIONS ============ //

    /// @notice Returns the facility the lens reads.
    /// @return The facility address.
    function facility() external view returns (address);

    /// @notice Returns the yield a weekly reset running now would project for the vault:
    ///         the vault yield accrued since the snapshots, plus the weekly Clearinghouse
    ///         interest for the backing vault, multiplied by the vault's buyback share.
    /// @dev This is a live projection; the stored next yield is available through
    ///      `getAssetConfig` of the facility. The projection applies the rate change
    ///      since the last weekly reset to the balance snapshot taken at that reset:
    ///      protocol balance changes made after the snapshot do not enter the projection
    ///      until the following reset, and a stored projection overstated by an outflow
    ///      can be lowered through `decreaseNextYield`. Reverts with
    ///      `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an unregistered vault.
    /// @param vault_ The registered vault.
    /// @return yield The projected yield, in reserve units.
    function getNextYield(address vault_) external view returns (uint256 yield);

    /// @notice Returns the reserve value of the protocol-held shares of a vault: the
    ///         treasury balance, and for the backing vault also the balances of the
    ///         active Clearinghouses, valued by the redemption class of the vault
    ///         (floor).
    /// @dev Reverts with `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an
    ///      unregistered vault.
    /// @param vault_ The registered vault.
    /// @return balance The reserve value, in reserve units.
    function getReserveBalance(address vault_) external view returns (uint256 balance);

    /// @notice Returns the weekly Clearinghouse interest a weekly reset running now would
    ///         credit to the backing vault.
    /// @dev Zero when no backing vault is designated. The reads of the Clearinghouses
    ///      are tolerant: an entry whose `reserve()` read reverts is counted only while
    ///      included, and an entry whose `principalReceivables()` read reverts
    ///      contributes nothing.
    /// @return yield The weekly interest, in backing reserve units.
    function getClearinghouseYield() external view returns (uint256 yield);

    /// @notice Returns the Clearinghouse component of the backing yield per registry
    ///         entry, in registry order.
    /// @dev The interest of the counted entries sums to `getClearinghouseYield`. With no
    ///      backing vault designated, no entry is counted.
    /// @return breakdown The per-entry breakdown.
    function getClearinghouseBreakdown()
        external
        view
        returns (ClearinghouseYield[] memory breakdown);

    /// @notice Returns the buyback pool of a vault: the facility's balances of the
    ///         vault's shares and reserve token, and their reserve value.
    /// @dev Reverts with `IYieldRepurchaseFacilityV2_AssetNotRegistered` for an
    ///      unregistered vault.
    /// @param vault_ The registered vault.
    /// @return pool The buyback pool.
    function getBuybackPool(address vault_) external view returns (BuybackPool memory pool);

    /// @notice Previews the capacity of the market the next daily cycle would open for
    ///         the vault from the pool held now, and the number of daily cycles that
    ///         cycle would see remaining in the week.
    /// @dev The preview sizes the bid as the daily cycle does: the pool value divided by
    ///      the remaining daily cycles (floor), with the idle reserve of a sell-shares
    ///      asset counted as the shares its deposit would mint, and the reserve shortfall
    ///      of a reserve-paying asset counted as covered by the redeem of the held shares.
    ///      It assumes the wrap and the redeem succeed and reads the balances held now:
    ///      a weekly reset or an OHM burn running on the same beat before the daily cycle
    ///      changes the pool first. The remaining daily cycles are derived from the
    ///      epoch counter: the next epoch that is a multiple of three, with the weekly
    ///      reset wrapping the counter to zero. A zero capacity means the cycle would
    ///      open no market. Reverts with `IYieldRepurchaseFacilityV2_AssetNotRegistered`
    ///      for an unregistered vault.
    /// @param vault_ The registered vault.
    /// @return capacity The previewed market capacity, in payout token units: the share
    ///         amount for a sell-shares asset, the reserve amount otherwise.
    /// @return daysRemaining The number of daily cycles remaining in the week at the
    ///         next daily cycle, including that one, in the range `[1, 7]`.
    function previewDailyBid(
        address vault_
    ) external view returns (uint256 capacity, uint256 daysRemaining);

    /// @notice Returns the tracked bond market of a vault and whether the auctioneer
    ///         reports it live.
    /// @dev The tracked market is the only purchasable market of the vault. `live` is
    ///      false when no market is tracked.
    /// @param vault_ The vault.
    /// @return tracked Whether a market is tracked for the vault.
    /// @return marketId The tracked market id; zero when none is tracked.
    /// @return live Whether the auctioneer reports the tracked market live.
    function getVaultMarket(
        address vault_
    ) external view returns (bool tracked, uint256 marketId, bool live);

    /// @notice Returns the reserve token of the vault that funds a market created by the
    ///         facility on its current bond auctioneer.
    /// @param marketId_ The market ID.
    /// @return reserve The reserve token, or the zero address when the market was not
    ///         created by the facility on the current bond auctioneer.
    function marketReserve(uint256 marketId_) external view returns (address reserve);

    /// @notice Returns the price gate of the daily cycles: whether the OHM price
    ///         denominated in the backing reserve is at or above the backing value, and
    ///         the two values compared.
    /// @dev Mirrors the gate of `IPeriodicTask.execute`, and reverts where it reverts:
    ///      when the `PRICE.getPriceIn` read of the backing reserve reverts, including
    ///      when no backing vault is designated, or when the backing oracle read
    ///      reverts.
    /// @return open Whether the daily cycles open markets.
    /// @return gatePrice The OHM price denominated in the backing reserve, in oracle
    ///         decimals.
    /// @return backing The backing value, in 18 decimals.
    function priceGate() external view returns (bool open, uint256 gatePrice, uint256 backing);
}
