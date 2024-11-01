// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

interface IReserveMigrator {
    // ========== ERRORS ========== //

    error ReserveMigrator_InvalidParams();
    error ReserveMigrator_BadMigration();

    // ========== EVENTS ========== //

    event MigratedReserves(address indexed from, address indexed to, uint256 amount);
    event Activated();
    event Deactivated();

    // ========== MIGRATE ========== //

    /// @notice migrate reserves and wrapped reserves in the treasury to the new reserve token
    /// @dev this function is restricted to the heart role to avoid complications with opportunistic conversions
    /// @dev if no migration is required or it is deactivated, the function does nothing
    function migrate() external;
}
