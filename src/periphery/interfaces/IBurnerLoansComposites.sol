// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

/// @title Burner Loans Composites Interface
/// @notice One-transaction borrower flows composed from Burner Loans primitives.
interface IBurnerLoansComposites {
    /// @notice Thrown when a required address is zero.
    error BurnerLoansComposites_ZeroAddress();

    /// @notice Thrown when a required token amount is zero.
    error BurnerLoansComposites_ZeroAmount();

    /// @notice Thrown when the configured Burner Loans contract is incompatible.
    /// @param burnerLoans The incompatible Burner Loans contract.
    error BurnerLoansComposites_InvalidBurnerLoans(address burnerLoans);

    /// @notice Thrown when the configured OHM token differs from Burner Loans' OHM token.
    /// @param expectedOhm The OHM token reported by Burner Loans.
    /// @param actualOhm The OHM token supplied to the constructor.
    error BurnerLoansComposites_OhmMismatch(address expectedOhm, address actualOhm);

    /// @notice Thrown when a signature authorizes a different account from the caller.
    /// @param account The account named by the authorization.
    /// @param caller The caller submitting the authorization.
    error BurnerLoansComposites_InvalidAuthorizationAccount(address account, address caller);

    /// @notice Thrown when an authorization targets an operator other than this contract.
    /// @param operator The operator named by the authorization.
    error BurnerLoansComposites_InvalidAuthorizationOperator(address operator);

    /// @notice Thrown when a result recipient is invalid.
    /// @param recipient The invalid recipient.
    error BurnerLoansComposites_InvalidRecipient(address recipient);

    /// @notice Thrown when a composite flow does not restore its starting token balance.
    /// @param token The token with the unexpected balance.
    /// @param expected The expected ending balance.
    /// @param actual The observed ending balance.
    error BurnerLoansComposites_UnexpectedBalance(address token, uint256 expected, uint256 actual);

    /// @notice Inputs for atomically depositing collateral and borrowing OHM.
    /// @param asset The collateral asset.
    /// @param collateralAmount The collateral amount, in collateral-token decimals.
    /// @param ohmAmount The OHM amount to borrow, in OHM token decimals.
    /// @param recipient The recipient of the borrowed OHM.
    /// @param maxFee The maximum collateral fee accepted by the caller.
    struct DepositAndBorrowParams {
        address asset;
        uint128 collateralAmount;
        uint128 ohmAmount;
        address recipient;
        uint256 maxFee;
    }

    /// @notice Results from atomically depositing collateral and borrowing OHM.
    /// @param depositedCollateral The collateral deposited by this call.
    /// @param totalCollateral The position's resulting collateral balance.
    /// @param fee The collateral fee charged.
    /// @param resultingDebtOhm The position's resulting OHM debt.
    /// @param maturity The position's resulting maturity timestamp.
    /// @param healthFactor The position's resulting health factor.
    struct DepositAndBorrowResult {
        uint256 depositedCollateral;
        uint256 totalCollateral;
        uint256 fee;
        uint256 resultingDebtOhm;
        uint48 maturity;
        uint256 healthFactor;
    }

    /// @notice Inputs for atomically repaying OHM and withdrawing collateral.
    /// @param asset The collateral asset.
    /// @param maxRepayOhm The maximum OHM amount to repay, in OHM token decimals.
    /// @param collateralAmount The collateral amount to withdraw, in collateral-token decimals.
    /// @param recipient The recipient of the withdrawn collateral.
    struct RepayAndWithdrawParams {
        address asset;
        uint128 maxRepayOhm;
        uint128 collateralAmount;
        address recipient;
    }

    /// @notice Results from atomically repaying OHM and withdrawing collateral.
    /// @param repaidOhm The OHM debt repaid.
    /// @param refundedOhm The unused OHM returned to the caller.
    /// @param tokenOut The collateral token returned by Burner Loans.
    /// @param amountOut The collateral-token amount returned to the recipient.
    /// @param remainingCollateral The position's remaining collateral balance.
    /// @param healthFactor The position's resulting health factor.
    struct RepayAndWithdrawResult {
        uint256 repaidOhm;
        uint256 refundedOhm;
        address tokenOut;
        uint256 amountOut;
        uint256 remainingCollateral;
        uint256 healthFactor;
    }

    /// @notice Emitted when an unused input-token balance is returned to the caller.
    /// @param token The refunded token.
    /// @param caller The account receiving the refund.
    /// @param amount The refunded token amount.
    event TokenRefunded(address indexed token, address indexed caller, uint256 amount);

    /// @notice Deposits collateral and borrows OHM for the caller in one transaction.
    /// @dev An optional signature may authorize this contract as the caller's Burner Loans
    ///      operator. Reverts for invalid parameters, authorization, transfers, or underlying
    ///      Burner Loans operations.
    /// @param authorization Optional operator authorization for this contract.
    /// @param signature Signature over `authorization`.
    /// @param params Deposit and borrow parameters.
    /// @return result The resulting position and fee data.
    function depositAndBorrow(
        IOperatorAuth.Authorization calldata authorization,
        IOperatorAuth.Signature calldata signature,
        DepositAndBorrowParams calldata params
    ) external returns (DepositAndBorrowResult memory result);

    /// @notice Repays OHM and withdraws collateral for the caller in one transaction.
    /// @dev An optional signature may authorize this contract as the caller's Burner Loans
    ///      operator. Any unused OHM is refunded to the caller. Reverts for invalid parameters,
    ///      authorization, transfers, or underlying Burner Loans operations.
    /// @param authorization Optional operator authorization for this contract.
    /// @param signature Signature over `authorization`.
    /// @param params Repayment and withdrawal parameters.
    /// @return result The resulting repayment, refund, collateral, and health data.
    function repayAndWithdraw(
        IOperatorAuth.Authorization calldata authorization,
        IOperatorAuth.Signature calldata signature,
        RepayAndWithdrawParams calldata params
    ) external returns (RepayAndWithdrawResult memory result);

    /// @notice Returns the Burner Loans contract used by the composite flows.
    /// @return address The Burner Loans contract.
    function burnerLoans() external view returns (address);

    /// @notice Returns the OHM token used by the composite flows.
    /// @return address The OHM token.
    function ohm() external view returns (address);
}
