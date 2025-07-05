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

    error DepositFacility_InvalidAddress(address operator);

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

    /// @notice Allows an operator to commit funds. This will ensure that enough funds are available to honour the commitments.
    ///
    /// @param depositToken_ The deposit token committed
    /// @param depositPeriod_ The deposit period in months
    /// @param amount_ The amount to commit
    function handleCommit(IERC20 depositToken_, uint8 depositPeriod_, uint256 amount_) external;

    /// @notice Allows an operator to cancel committed funds.
    ///
    /// @param depositToken_ The deposit token committed
    /// @param depositPeriod_ The deposit period in months
    /// @param amount_ The amount to cancel the committed funds by
    function handleCommitCancel(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external;

    /// @notice Allows an operator to withdraw committed funds
    ///
    /// @param depositToken_ The deposit token to withdraw
    /// @param depositPeriod_ The deposit period in months
    /// @param amount_ The amount to withdraw
    /// @param recipient_ The address to receive the deposit tokens
    /// @return actualAmount The amount of tokens transferred
    function handleCommitWithdraw(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address recipient_
    ) external returns (uint256 actualAmount);

    /// @notice Allows an operator to borrow against deposits owned by this facility
    ///
    /// @param depositToken_ The deposit token to borrow against
    /// @param depositPeriod_ The deposit period in months
    /// @param amount_ The amount to borrow
    /// @param recipient_ The address to receive the borrowed tokens
    /// @return actualAmount The amount of tokens borrowed
    function handleBorrow(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address recipient_
    ) external returns (uint256 actualAmount);

    /// @notice Allows an operator to repay borrowed funds
    ///
    /// @param depositToken_ The deposit token being repaid
    /// @param depositPeriod_ The deposit period in months
    /// @param amount_ The amount being repaid
    /// @param payer_ The address making the repayment
    /// @return actualAmount The amount of tokens borrowed
    function handleRepay(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address payer_
    ) external returns (uint256 actualAmount);

    // ========== BALANCE QUERIES ========== //

    /// @notice Get the available deposit balance for a specific token. This excludes any committed funds.
    ///
    /// @param depositToken_ The deposit token to query
    /// @return balance     The available deposit balance
    function getAvailableDeposits(IERC20 depositToken_) external view returns (uint256 balance);

    /// @notice Get the committed deposits for a specific token and operator
    ///
    /// @param depositToken_ The deposit token to query
    /// @param operator_     The operator
    /// @return committed   The total committed deposits
    function getCommittedDeposits(
        IERC20 depositToken_,
        address operator_
    ) external view returns (uint256 committed);
}
