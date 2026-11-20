// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Constants
/// @notice Shared compile-time constants for Burner Loans and its config timelock.
library LoanParameters {
    /// @dev Maximum supported token precision; bounds decimal scaling in risk arithmetic.
    uint8 internal constant _MAX_TOKEN_DECIMALS = 36;

    /// @dev DepositManager period reserved for Burner Loans collateral.
    uint8 internal constant _DEPOSIT_PERIOD = 1;

    /// @dev Basis-point denominator.
    uint16 internal constant _MAX_BPS = 10_000;

    /// @dev Maximum aggregate fee rate in basis points.
    uint16 internal constant _FEE_CAP_BPS = 10_000;

    /// @dev Maximum loan-to-value ratio in basis points.
    uint16 internal constant _MAX_LTV_BPS = 10_000;

    /// @dev Maximum backing multiplier in basis points.
    uint16 internal constant _MAX_BACKING_MULTIPLIER_BPS = 50_000;

    /// @dev Maximum configurable term length.
    uint48 internal constant _MAX_TERM_LENGTH = 365 days;

    /// @dev Maximum configurable maturity horizon.
    uint48 internal constant _MAX_MATURITY_HORIZON = 366 days;

    /// @dev Grace period during which an authorized caller can re-enable Burner Loans.
    uint32 internal constant _REENABLE_GRACE_PERIOD = 7 days;
}
