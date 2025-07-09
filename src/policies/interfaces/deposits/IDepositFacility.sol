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

    event AssetCommitted(address indexed asset, address indexed operator, uint256 amount);

    event AssetCommitCancelled(address indexed asset, address indexed operator, uint256 amount);

    event AssetCommitWithdrawn(address indexed asset, address indexed operator, uint256 amount);

    event Reclaimed(
        address indexed user,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 reclaimedAmount,
        uint256 forfeitedAmount
    );

    // ========== ERRORS ========== //

    error DepositFacility_ZeroAmount();

    error DepositFacility_InvalidAddress(address operator);

    error DepositFacility_UnauthorizedOperator(address operator);

    error DepositFacility_InvalidRedemption();

    error DepositFacility_InsufficientDeposits(uint256 requested, uint256 available);

    error DepositFacility_InsufficientCommitment(
        address operator,
        uint256 requested,
        uint256 available
    );

    // ========== OPERATOR AUTHORIZATION ========== //

    /// @notice Authorize an operator (e.g., a redemption vault) to handle actions through this facility
    ///
    /// @param  operator_   The address of the operator to authorize
    function authorizeOperator(address operator_) external;

    /// @notice Deauthorize an operator
    ///
    /// @param  operator_   The address of the operator to deauthorize
    function deauthorizeOperator(address operator_) external;

    /// @notice Check if an operator is authorized
    ///
    /// @param  operator_       The address of the operator to check
    /// @return isAuthorized    True if the operator is authorized
    function isAuthorizedOperator(address operator_) external view returns (bool isAuthorized);

    /// @notice Get the list of operators authorized to handle actions through this facility
    ///
    /// @return operators   The list of operators
    function getOperators() external view returns (address[] memory operators);

    // ========== REDEMPTION HANDLING ========== //

    /// @notice Allows an operator to commit funds. This will ensure that enough funds are available to honour the commitments.
    ///
    /// @param depositToken_    The deposit token committed
    /// @param depositPeriod_   The deposit period in months
    /// @param amount_ The amount to commit
    function handleCommit(IERC20 depositToken_, uint8 depositPeriod_, uint256 amount_) external;

    /// @notice Allows an operator to cancel committed funds.
    ///
    /// @param depositToken_    The deposit token committed
    /// @param depositPeriod_   The deposit period in months
    /// @param amount_ The amount to cancel the committed funds by
    function handleCommitCancel(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external;

    /// @notice Allows an operator to withdraw committed funds
    ///
    /// @param depositToken_    The deposit token to withdraw
    /// @param depositPeriod_   The deposit period in months
    /// @param amount_          The amount to withdraw
    /// @param recipient_       The address to receive the deposit tokens
    /// @return actualAmount    The amount of tokens transferred
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

    // ========== RECLAIM ========== //

    /// @notice Preview the amount of deposit token that would be reclaimed
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Returning the total amount of deposit tokens that would be reclaimed
    ///
    /// @param  depositToken_   The address of the deposit token
    /// @param  depositPeriod_  The period of the deposit in months
    /// @param  amount_         The amount of deposit tokens to reclaim
    /// @return reclaimed       The amount of deposit token returned to the caller
    function previewReclaim(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external view returns (uint256 reclaimed);

    /// @notice Reclaims deposit tokens, after applying a discount
    ///         Deposit tokens can be reclaimed at any time.
    ///         The caller is not required to have a position in the facility.
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Burning the receipt tokens
    ///         - Transferring the deposit token to `recipient_`
    ///         - Emitting an event
    ///
    /// @param  depositToken_   The address of the deposit token
    /// @param  depositPeriod_  The period of the deposit in months
    /// @param  recipient_      The address to reclaim the deposit token to
    /// @param  amount_         The amount of deposit tokens to reclaim
    /// @return reclaimed       The amount of deposit token returned to the recipient
    function reclaimFor(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        address recipient_,
        uint256 amount_
    ) external returns (uint256 reclaimed);

    /// @notice Reclaims deposit tokens, after applying a discount
    /// @dev    This variant reclaims the underlying asset to the caller
    ///
    /// @param  depositToken_   The address of the deposit token
    /// @param  depositPeriod_  The period of the deposit in months
    /// @param  amount_         The amount of deposit tokens to reclaim
    /// @return reclaimed       The amount of deposit token returned to the caller
    function reclaim(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external returns (uint256 reclaimed);

    // ========== BALANCE QUERIES ========== //

    /// @notice Get the available deposit balance for a specific token. This excludes any committed funds.
    ///
    /// @param depositToken_ The deposit token to query
    /// @return balance     The available deposit balance
    function getAvailableDeposits(IERC20 depositToken_) external view returns (uint256 balance);

    /// @notice Get the committed deposits for a specific token
    ///
    /// @param depositToken_    The deposit token to query
    /// @return committed       The total committed deposits
    function getCommittedDeposits(IERC20 depositToken_) external view returns (uint256 committed);

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
