// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Constants
/// @notice Shared compile-time constants for Burner Loans and its config timelock.
library BurnerLoansConstants {
    uint8 internal constant DEPOSIT_PERIOD = 1;
    uint16 internal constant MAX_BPS = 10_000;
    uint16 internal constant FEE_CAP_BPS = 10_000;
    uint16 internal constant MAX_COLLATERAL_FACTOR_BPS = 10_000;
    uint16 internal constant MAX_COLLATERAL_RATIO_BPS = 50_000;
    uint16 internal constant MAX_BACKING_MULTIPLIER_BPS = 50_000;
    uint48 internal constant MAX_TERM_LENGTH = 365 days;
    uint48 internal constant MAX_MATURITY_HORIZON = 366 days;
    uint256 internal constant MAX_KEEPER_REWARD = type(uint128).max;
    uint32 internal constant REENABLE_GRACE_PERIOD = 7 days;
}
