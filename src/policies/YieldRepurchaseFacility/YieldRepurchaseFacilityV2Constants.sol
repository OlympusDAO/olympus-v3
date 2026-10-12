// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title YieldRepurchaseFacilityV2Constants
/// @notice Shared compile-time constants of the YieldRepurchaseFacilityV2, its linked
///         libraries, and its configuration policies.
/// @dev The constants that only one contract uses, such as the bond market shape of
///      `YRFBondMarketLib`, the Clearinghouse rate of `YRFClearinghouseLib`, or the
///      module keycodes and the `enable` payload layout of the facility, stay with that
///      contract.
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
}
