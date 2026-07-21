// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

/// @title Burner Loans Composites Interface
/// @notice One-transaction borrower flows composed from Burner Loans primitives.
interface IBurnerLoansComposites {
    error BurnerLoansComposites_ZeroAddress();
    error BurnerLoansComposites_ZeroAmount();
    error BurnerLoansComposites_InvalidAuthorizationAccount(address account, address caller);
    error BurnerLoansComposites_InvalidAuthorizationOperator(address operator);
    error BurnerLoansComposites_InvalidRecipient(address recipient);
    error BurnerLoansComposites_UnexpectedBalance(address token, uint256 expected, uint256 actual);

    struct DepositAndBorrowParams {
        address asset;
        uint128 collateralAmount;
        uint128 ohmAmount;
        address recipient;
        uint256 maxFee;
    }

    struct DepositAndBorrowResult {
        uint256 depositedCollateral;
        uint256 totalCollateral;
        uint256 fee;
        uint256 resultingDebtOhm;
        uint48 maturity;
        uint256 healthFactor;
    }

    struct RepayAndWithdrawParams {
        address asset;
        uint128 maxRepayOhm;
        uint128 collateralAmount;
        address recipient;
    }

    struct RepayAndWithdrawResult {
        uint256 repaidOhm;
        uint256 refundedOhm;
        address tokenOut;
        uint256 amountOut;
        uint256 remainingCollateral;
        uint256 healthFactor;
    }

    event TokenRefunded(address indexed token, address indexed caller, uint256 amount);

    function depositAndBorrow(
        IOperatorAuth.Authorization calldata authorization,
        IOperatorAuth.Signature calldata signature,
        DepositAndBorrowParams calldata params
    ) external returns (DepositAndBorrowResult memory result);

    function repayAndWithdraw(
        IOperatorAuth.Authorization calldata authorization,
        IOperatorAuth.Signature calldata signature,
        RepayAndWithdrawParams calldata params
    ) external returns (RepayAndWithdrawResult memory result);

    function burnerLoans() external view returns (address);

    function ohm() external view returns (address);
}
