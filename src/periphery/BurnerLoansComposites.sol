// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";

import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";

// Contracts
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {ERC165} from "@openzeppelin-5.7.0/utils/introspection/ERC165.sol";
import {SafeERC20Exact as ExactERC20} from "src/libraries/SafeERC20Exact.sol";
import {BurnerLoansCollateral} from "src/policies/burnerloans/BurnerLoansCollateral.sol";
import {BurnerLoansDebt} from "src/policies/burnerloans/BurnerLoansDebt.sol";

/// @title Burner Loans Composites
/// @notice One-transaction borrower flows composed from Burner Loans primitives.
contract BurnerLoansComposites is
    IBurnerLoansComposites,
    IVersioned,
    ERC165,
    ReentrancyGuardTransient
{
    using SafeERC20 for IERC20;

    address internal immutable _BURNER_LOANS;
    address internal immutable _OHM;
    BurnerLoansCollateral public immutable collateral;
    BurnerLoansDebt public immutable debt;

    /// @notice Binds the composite flows to one Burner Loans policy and its configured OHM token.
    /// @dev Reverts if:
    ///      - A required address is zero or a target interface is unsupported.
    ///      - The target context is unavailable.
    ///      - OHM differs from the target's immutable debt token.
    constructor(
        address burnerLoans_,
        address ohm_,
        BurnerLoansCollateral collateral_,
        BurnerLoansDebt debt_
    ) {
        if (burnerLoans_ == address(0) || ohm_ == address(0)) {
            revert BurnerLoansComposites_ZeroAddress();
        }
        if (
            !ERC165Checker.supportsInterface(burnerLoans_, type(IBurnerLoansCore).interfaceId) ||
            address(collateral_.core()) != burnerLoans_ ||
            address(debt_.core()) != burnerLoans_
        ) revert BurnerLoansComposites_InvalidBurnerLoans(burnerLoans_);
        collateral = collateral_;
        debt = debt_;
        address expectedOhm = IBurnerLoansCore(burnerLoans_).ohm();
        if (expectedOhm != ohm_) revert BurnerLoansComposites_OhmMismatch(expectedOhm, ohm_);
        _BURNER_LOANS = burnerLoans_;
        _OHM = ohm_;
    }

    /// @inheritdoc IBurnerLoansComposites
    /// @dev Reverts if:
    ///      - An input parameter is invalid.
    ///      - Operator authorization fails.
    ///      - A token transfer fails.
    ///      - An underlying Burner Loans operation fails.
    function depositAndBorrow(
        IOperatorAuth.Authorization calldata authorization_,
        IOperatorAuth.Signature calldata signature_,
        DepositAndBorrowParams calldata params_
    ) external nonReentrant returns (DepositAndBorrowResult memory result) {
        if (params_.asset == address(0)) revert BurnerLoansComposites_ZeroAddress();
        if (params_.collateralAmount == 0 || params_.ohmAmount == 0) {
            revert BurnerLoansComposites_ZeroAmount();
        }
        _validateRecipient(params_.recipient);
        _authorizeIfProvided(authorization_, signature_);

        IERC20 asset = IERC20(params_.asset);
        uint256 startingBalance = asset.balanceOf(address(this));
        uint256 inputAmount = uint256(params_.collateralAmount) + params_.maxFee;
        ExactERC20.safeTransferFromExact(asset, msg.sender, address(this), inputAmount);
        asset.forceApprove(_BURNER_LOANS, inputAmount);

        // The subsequent borrow supplies final health; deposit health is not needed.
        // This multiline operation needs a range; the suppression ends immediately after it.
        // forge-lint: disable-start(unused-return)
        (result.depositedCollateral, result.totalCollateral, ) = collateral.depositCollateral(
            params_.asset,
            params_.collateralAmount,
            msg.sender
        );
        // forge-lint: disable-end(unused-return)
        IBurnerLoansDebt.BorrowPreview memory borrowed = debt.borrow(
            params_.asset,
            params_.ohmAmount,
            msg.sender,
            params_.recipient,
            params_.maxFee
        );
        result.fee = borrowed.fee;
        result.resultingDebtOhm = borrowed.resultingDebtOhm;
        result.maturity = borrowed.maturity;
        result.healthFactor = borrowed.resultingHealthFactor;

        asset.forceApprove(_BURNER_LOANS, 0);
        _refund(asset, msg.sender, startingBalance);
    }

    /// @inheritdoc IBurnerLoansComposites
    /// @dev Reverts if:
    ///      - An input parameter is invalid.
    ///      - Operator authorization fails.
    ///      - A token transfer fails.
    ///      - An underlying Burner Loans operation fails.
    function repayAndWithdraw(
        IOperatorAuth.Authorization calldata authorization_,
        IOperatorAuth.Signature calldata signature_,
        RepayAndWithdrawParams calldata params_
    ) external nonReentrant returns (RepayAndWithdrawResult memory result) {
        if (params_.asset == address(0)) revert BurnerLoansComposites_ZeroAddress();
        if (params_.maxRepayOhm == 0 && params_.collateralAmount == 0) {
            revert BurnerLoansComposites_ZeroAmount();
        }
        _validateRecipient(params_.recipient);
        _authorizeIfProvided(authorization_, signature_);

        (, , IFLOANv1.Position memory position) = LoanPositions.forCore(
            IBurnerLoansCore(_BURNER_LOANS),
            params_.asset,
            msg.sender
        );
        result.repaidOhm = params_.maxRepayOhm < position.principalDue
            ? params_.maxRepayOhm
            : position.principalDue;
        result.resultingDebtOhm = position.principalDue;
        result.healthFactor = type(uint256).max;

        IERC20 ohmToken = IERC20(_OHM);
        uint256 startingOhmBalance = ohmToken.balanceOf(address(this));
        if (params_.maxRepayOhm != 0) {
            ExactERC20.safeTransferFromExact(
                ohmToken,
                msg.sender,
                address(this),
                params_.maxRepayOhm
            );
        }
        if (result.repaidOhm != 0) {
            ohmToken.forceApprove(_BURNER_LOANS, result.repaidOhm);
            (result.resultingDebtOhm, result.healthFactor) = debt.repay(
                params_.asset,
                result.repaidOhm,
                msg.sender
            );
            ohmToken.forceApprove(_BURNER_LOANS, 0);
        }

        if (params_.collateralAmount != 0) {
            IBurnerLoansCollateral.WithdrawPreview memory withdrawn = collateral.withdrawCollateral(
                params_.asset,
                params_.collateralAmount,
                msg.sender,
                params_.recipient
            );
            result.tokenOut = withdrawn.returnToken;
            result.amountOut = withdrawn.returnAmount;
            result.remainingCollateral = withdrawn.remainingDepositedCollateral;
            result.healthFactor = withdrawn.resultingHealthFactor;
        } else {
            result.remainingCollateral = position.collateral;
            if (result.repaidOhm == 0 && position.principalDue != 0) {
                IBurnerLoansRisk evaluator = IBurnerLoansRisk(
                    IBurnerLoansCore(_BURNER_LOANS).risk()
                );
                result.healthFactor = evaluator.health(
                    evaluator.snapshot(params_.asset),
                    IBurnerLoansCore(_BURNER_LOANS).marketId(params_.asset),
                    position.collateral,
                    position.principalDue
                );
            }
        }

        result.refundedOhm = _refund(ohmToken, msg.sender, startingOhmBalance);
    }

    /// @inheritdoc IBurnerLoansComposites
    function burnerLoans() external view override returns (address) {
        return _BURNER_LOANS;
    }

    /// @inheritdoc IBurnerLoansComposites
    function ohm() external view override returns (address) {
        return _OHM;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId_) public view override returns (bool supported) {
        return
            interfaceId_ == type(IVersioned).interfaceId ||
            interfaceId_ == type(IBurnerLoansComposites).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    function _authorizeIfProvided(
        IOperatorAuth.Authorization calldata authorization_,
        IOperatorAuth.Signature calldata signature_
    ) private {
        if (authorization_.account == address(0)) return;
        if (authorization_.account != msg.sender) {
            revert BurnerLoansComposites_InvalidAuthorizationAccount(
                authorization_.account,
                msg.sender
            );
        }
        if (authorization_.authorized != address(this)) {
            revert BurnerLoansComposites_InvalidAuthorizationOperator(authorization_.authorized);
        }
        IOperatorAuth(_BURNER_LOANS).setAuthorizationWithSig(authorization_, signature_);
    }

    function _validateRecipient(address recipient_) private view {
        if (recipient_ == address(0) || recipient_ == address(this)) {
            revert BurnerLoansComposites_InvalidRecipient(recipient_);
        }
    }

    function _refund(
        IERC20 token_,
        address recipient_,
        uint256 startingBalance_
    ) private returns (uint256 refunded) {
        uint256 currentBalance = token_.balanceOf(address(this));
        if (currentBalance < startingBalance_) {
            revert BurnerLoansComposites_UnexpectedBalance(
                address(token_),
                startingBalance_,
                currentBalance
            );
        }
        refunded = currentBalance - startingBalance_;
        if (refunded != 0) {
            token_.safeTransfer(recipient_, refunded);
            emit TokenRefunded(address(token_), recipient_, refunded);
        }
        uint256 finalBalance = token_.balanceOf(address(this));
        if (finalBalance != startingBalance_) {
            revert BurnerLoansComposites_UnexpectedBalance(
                address(token_),
                startingBalance_,
                finalBalance
            );
        }
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }
}
