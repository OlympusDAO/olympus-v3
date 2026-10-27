// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title YieldRepurchaseFacilityV2Constants
/// @notice Shared compile-time constants of the YieldRepurchaseFacilityV2, its linked
///         libraries, and its configuration policies.
/// @dev The constants that only one contract uses, such as the bond market shape of
///      `YieldRepurchaseFacilityV2BondMarketLib`, the Clearinghouse rate of
///      `YieldRepurchaseFacilityV2MathLib`, the module keycodes of
///      `YieldRepurchaseFacilityV2DependenciesLib`, or the `enable` payload layout of the
///      facility, stay with that contract.
library YieldRepurchaseFacilityV2Constants {
    // ============ SCALES ============ //

    /// @notice Base of the power-of-ten decimal scales: one whole unit of a value with
    ///         `decimals` decimals is `DECIMAL_BASE ** decimals`.
    uint256 internal constant DECIMAL_BASE = 10;

    /// @notice Precision denominator of the percentage parameters (`1e18` = 100%): the
    ///         yield buyback share, the initial discount, and the max price premium.
    uint256 internal constant ONE_HUNDRED_PERCENT = 1e18;

    /// @notice Decimals of the backing value, and therefore the decimals both the
    ///         `PRICE` module and the backing oracle must report so that the oracle
    ///         price can be compared against the backing.
    uint8 internal constant BACKING_DECIMALS = 18;

    /// @notice Maximum reserve token decimals supported when adding a vault.
    /// @dev The backing amount of the burned OHM is scaled down from the backing
    ///      decimals to the reserve decimals, so a reserve cannot carry more decimals
    ///      than the backing.
    uint8 internal constant MAX_RESERVE_DECIMALS = BACKING_DECIMALS;

    // ============ SCHEDULE ============ //

    /// @notice Number of epochs per day.
    uint48 internal constant EPOCHS_PER_DAY = 3;

    /// @notice Number of days per week.
    uint256 internal constant DAYS_PER_WEEK = 7;

    /// @notice Number of epochs per week (3 per day * 7 days).
    uint48 internal constant EPOCH_LENGTH = 21;

    // ============ PARAMETER BOUNDS ============ //

    /// @notice Exclusive upper bound of the re-enable grace window: the window must be
    ///         strictly shorter than one weekly cycle.
    uint32 internal constant MAX_GRACE_PERIOD = 7 days;

    /// @notice Upper bound of the max price premium (`1e18` = 100%), inclusive.
    /// @dev The bound guards against a mis-entered value; it is not an economic limit.
    ///      The premium caps the payout at `oraclePrice * (1 + maxPricePremium)`, so the
    ///      bound caps that payout at 11x the oracle price, far above any usable market
    ///      ceiling. The premium only lowers the market's minimum price, so no premium
    ///      magnitude can overflow the market pricing.
    uint256 internal constant MAX_PRICE_PREMIUM_LIMIT = 10e18;

    /// @notice Lower bound of the step gas limit, inclusive, in gas units.
    /// @dev The bound guards against a mis-entered value; it does not guarantee that a
    ///      step fits into the limit. The gas a step needs depends on the vault, on the
    ///      feeds the PRICE module resolves, and on the bond contracts. The bound is
    ///      placed near the limit the costliest step measured on a mainnet fork (block
    ///      25_680_000) needs: about 1_040_000 gas for a daily cycle that wraps an idle
    ///      reserve, closes the previous market, and creates a market on bond contracts
    ///      not accessed earlier in the transaction.
    uint32 internal constant MIN_STEP_GAS_LIMIT = 1_100_000;

    /// @notice Upper bound of the step gas limit, inclusive, in gas units.
    /// @dev A beat runs up to `2 * N + 1` isolated steps for `N` enabled vaults, and
    ///      each step can consume the whole limit, so the bound caps the gas a beat can
    ///      be made to consume.
    uint32 internal constant MAX_STEP_GAS_LIMIT = 5_000_000;

    // ============ ISOLATED CALLS ============ //

    /// @notice Maximum bytes of returndata captured from an isolated call.
    /// @dev The cap bounds the memory expansion of the capture, so a callee returning or
    ///      reverting with oversized returndata cannot inflate the gas cost of the
    ///      caller. A success return is decoded only when its expected length fits under
    ///      the cap.
    uint16 internal constant MAX_RETURNDATA_LENGTH = 256;

    /// @notice Divisor that yields the gas a calling frame keeps back when it forwards a
    ///         given amount of gas to a call.
    /// @dev A call forwards at most 63/64 of the gas available to the calling frame
    ///      (EIP-150). Forwarding `limit` in full therefore requires
    ///      `limit + limit / 63` gas at the call: with `limit = 63 * q + r` and
    ///      `r < 63`, the frame holds `64 * q + r`, keeps back `q`, and forwards
    ///      `63 * q + r`.
    uint256 internal constant STEP_GAS_RETENTION_DIVISOR = 63;

    /// @notice Gas an isolated step requires on top of its gas limit and of the gas the
    ///         calling frame keeps back, in gas units.
    /// @dev The margin covers the gas the facility spends around one step, outside the
    ///      step itself: between the gas check and the call, and between the return of a
    ///      failed step and the gas check of the following step (the capture of the
    ///      returndata, the skip event, and the read of the next vault). That gas
    ///      measures 7_743 around a step that ran out of gas, whose skip event carries
    ///      an empty reason, and 9_872 around a step that reverted with at least
    ///      `MAX_RETURNDATA_LENGTH` bytes of data, in both cases with the next vault read
    ///      from storage slots not accessed earlier in the transaction (the facility
    ///      compiled by solc 0.8.36 with 400 optimizer runs, the Prague gas schedule).
    ///      The value leaves about one half of the larger measurement as headroom. The
    ///      gas the calling frame keeps back, `limit / 63`, also remains with the
    ///      facility after the step; the margin does not count on it.
    uint256 internal constant STEP_GAS_MARGIN = 15_000;
}
