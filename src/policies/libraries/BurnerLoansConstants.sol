// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Constants
/// @notice Shared compile-time constants for Burner Loans and its config timelock.
library BurnerLoansConstants {
    /// @dev DepositManager period reserved for Burner Loans collateral.
    uint8 internal constant DEPOSIT_PERIOD = 1;

    /// @dev Basis-point denominator.
    uint16 internal constant MAX_BPS = 10_000;

    /// @dev Maximum aggregate fee rate in basis points.
    uint16 internal constant FEE_CAP_BPS = 10_000;

    /// @dev Maximum loan-to-value ratio in basis points.
    uint16 internal constant MAX_LTV_BPS = 10_000;

    /// @dev Maximum backing multiplier in basis points.
    uint16 internal constant MAX_BACKING_MULTIPLIER_BPS = 50_000;

    /// @dev Maximum configurable term length.
    uint48 internal constant MAX_TERM_LENGTH = 365 days;

    /// @dev Maximum configurable maturity horizon.
    uint48 internal constant MAX_MATURITY_HORIZON = 366 days;

    /// @dev Maximum keeper reward expressible by FLOAN's packed market configuration.
    uint256 internal constant MAX_KEEPER_REWARD = type(uint128).max;

    /// @dev Grace period during which an authorized caller can re-enable Burner Loans.
    uint32 internal constant REENABLE_GRACE_PERIOD = 7 days;
}
