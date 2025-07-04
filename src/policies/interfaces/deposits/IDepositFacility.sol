// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";

/// @title  IDepositFacility
/// @notice Interface for deposit facilities to coordinate with generic operators (e.g., redemption vaults)
interface IDepositFacility {
    // ========== EVENTS ========== //

    event OperatorAuthorized(address indexed operator);
    event OperatorDeauthorized(address indexed operator);

    // ========== ERRORS ========== //

    error DepositFacility_UnauthorizedOperator(address operator);
    error DepositFacility_InvalidRedemption();
    error DepositFacility_InsufficientDeposits(uint256 requested, uint256 available);

    // ========== OPERATOR AUTHORIZATION ========== //

    /// @notice Authorize an operator (e.g., a redemption vault) to handle actions through this facility
    /// @param operator_ The address of the operator to authorize
    function authorizeOperator(address operator_) external;

    /// @notice Deauthorize an operator
    /// @param operator_ The address of the operator to deauthorize
    function deauthorizeOperator(address operator_) external;

    /// @notice Check if an operator is authorized
    /// @param operator_ The address of the operator to check
    /// @return True if the operator is authorized
    function isAuthorizedOperator(address operator_) external view returns (bool);

    // ========== REDEMPTION HANDLING ========== //

    /// @notice Handle withdrawal through this facility
    /// @dev This function is called by an authorized operator to process withdrawals
    /// @param depositToken_ The deposit token to withdraw
    /// @param depositPeriod_ The deposit period in months
    /// @param amount_ The amount to withdraw
    /// @param recipient_ The address to receive the deposit tokens
    function handleWithdraw(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address recipient_
    ) external;

    /// @notice Handle borrowing against a redemption through this facility
    /// @dev This function is called by an authorized operator to process borrowing
    /// @param depositToken_ The deposit token to borrow against
    /// @param depositPeriod_ The deposit period in months
    /// @param amount_ The amount to borrow
    /// @param recipient_ The address to receive the borrowed tokens
    function handleBorrow(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address recipient_
    ) external;

    /// @notice Handle loan repayment through this facility
    /// @dev This function is called by an authorized operator to process loan repayments
    /// @param depositToken_ The deposit token being repaid
    /// @param depositPeriod_ The deposit period in months
    /// @param amount_ The amount being repaid
    /// @param payer_ The address making the repayment
    function handleRepay(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address payer_
    ) external;

    // ========== BALANCE QUERIES ========== //

    /// @notice Get the available deposit balance for a specific token
    /// @param depositToken_ The deposit token to query
    /// @return The available deposit balance
    function getDepositBalance(IERC20 depositToken_) external view returns (uint256);

    /// @notice Get the total committed deposits for a specific token
    /// @param depositToken_ The deposit token to query
    /// @return The total committed deposits
    function getCommittedDeposits(IERC20 depositToken_) external view returns (uint256);
}
