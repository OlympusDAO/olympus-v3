// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

/// @title Burner Loans Lifecycle Interface
/// @notice State-changing borrower lifecycle operations.
interface IBurnerLoansLifecycle is IBurnerLoans {
    /// @notice Binds the Burner Loans Inventory used for OHM funding and principal accounting.
    /// @dev Callable only by OCG admin while Burner Loans is globally disabled. The new
    ///      BurnerLoansInventory must be a same-Kernel compatible contract, use the same OHM, and be
    ///      permanently bound to this facility. It must be active and enabled before Burner Loans is
    ///      enabled. Version migration remains an operational responsibility and is not inferred
    ///      from the outgoing contract's accounting.
    function setInventory(address inventory_) external;

    /// @notice Sets the Burner Loans Config policy authorized to configure this facility.
    /// @dev Callable only by OCG admin while Burner Loans is globally disabled. The policy must be
    ///      same-Kernel, compatible, and currently point back to this facility.
    function setConfigurator(address configurator_) external;

    /// @notice Deposits exact-transfer collateral into a borrower's position.
    /// @dev Reverts when the safe token transfer fails or DepositManager observes an inexact receipt.
    ///      Callback attempts to another lifecycle action revert through the shared reentrancy guard.
    /// @return uint256 The collateral credited in collateral token decimals.
    /// @return uint256 The borrower's resulting collateral in collateral token decimals.
    function depositCollateral(address, uint128, address) external returns (uint256, uint256);

    /// @notice Withdraws credited collateral from a borrower's position.
    /// @dev Assumes governance admitted an exact-transfer asset. Reverts when the safe outgoing
    ///      transfer fails. Callback attempts to another lifecycle action revert through the shared
    ///      reentrancy guard.
    /// @return address The collateral token returned.
    /// @return uint256 The collateral assets withdrawn.
    /// @return uint256 The borrower's remaining collateral shares.
    /// @return uint256 The borrower's health factor after the withdrawal.
    function withdrawCollateral(
        address,
        uint128,
        address,
        address
    ) external returns (address, uint256, uint256, uint256);

    /// @notice Borrows OHM against a collateral position.
    /// @return uint256 The principal borrowed in OHM token decimals.
    /// @return uint256 The origination fee in OHM token decimals.
    /// @return uint256 The resulting principal in OHM token decimals.
    /// @return uint48 The resulting maturity timestamp.
    /// @return uint256 The resulting health factor.
    function borrow(
        address,
        uint128,
        address,
        address,
        uint256
    ) external returns (uint256, uint256, uint256, uint48, uint256);

    /// @notice Repays OHM principal for a borrower.
    function repay(address, uint128, address) external returns (uint256 healthFactor);

    /// @notice Extends an active position's maturity and charges any applicable fee.
    function extend(
        address,
        address,
        uint16,
        uint256
    ) external returns (uint256 fee, uint48 maturity, uint256 healthFactor);

    /// @notice Defaults eligible positions and routes seized collateral.
    /// @return uint256 The keeper reward in collateral token decimals.
    /// @return uint256 The collateral routed to treasury in collateral token decimals.
    function seize(address, address[] calldata) external returns (uint256, uint256);

    /// @notice Claims excess collateral yield for the treasury.
    function harvestYield(address) external returns (uint256 yieldClaimed);
}
