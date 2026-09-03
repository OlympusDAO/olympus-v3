// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {BurnerLoansContext, IBurnerLoansSeizureContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";

// Contracts
import {ERC165} from "@openzeppelin-5.3.0/utils/introspection/ERC165.sol";

/// @title Burner Loans Composites
/// @notice One-transaction borrower flows composed from Burner Loans primitives.
contract BurnerLoansComposites is IBurnerLoansComposites, ERC165, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    address public immutable override burnerLoans;
    address public immutable override ohm;

    /// @notice Binds the composite flows to one Burner Loans policy and its configured OHM token.
    /// @dev Reverts for zero addresses, unsupported target interfaces, an unavailable target
    ///      context, or an OHM address that differs from the target's immutable debt token.
    constructor(address burnerLoans_, address ohm_) {
        if (burnerLoans_ == address(0) || ohm_ == address(0)) {
            revert BurnerLoansComposites_ZeroAddress();
        }
        if (
            !ERC165Checker.supportsInterface(
                burnerLoans_,
                type(IBurnerLoansLifecycle).interfaceId
            ) ||
            !ERC165Checker.supportsInterface(burnerLoans_, type(IBurnerLoansView).interfaceId) ||
            !ERC165Checker.supportsInterface(burnerLoans_, type(IOperatorAuth).interfaceId)
        ) {
            revert BurnerLoansComposites_InvalidBurnerLoans(burnerLoans_);
        }
        BurnerLoansContext memory context;
        try IBurnerLoansSeizureContext(burnerLoans_).context() returns (
            BurnerLoansContext memory targetContext
        ) {
            context = targetContext;
        } catch {
            revert BurnerLoansComposites_InvalidBurnerLoans(burnerLoans_);
        }
        address expectedOhm = address(context.ohm);
        if (expectedOhm != ohm_) revert BurnerLoansComposites_OhmMismatch(expectedOhm, ohm_);
        burnerLoans = burnerLoans_;
        ohm = ohm_;
    }

    /// @inheritdoc IBurnerLoansComposites
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
        asset.safeTransferFrom(msg.sender, address(this), inputAmount);
        asset.forceApprove(burnerLoans, inputAmount);

        (result.depositedCollateral, result.totalCollateral) = IBurnerLoansLifecycle(burnerLoans)
            .depositCollateral(params_.asset, params_.collateralAmount, msg.sender);
        (
            ,
            result.fee,
            result.resultingDebtOhm,
            result.maturity,
            result.healthFactor
        ) = IBurnerLoansLifecycle(burnerLoans).borrow(
            params_.asset,
            params_.ohmAmount,
            msg.sender,
            params_.recipient,
            params_.maxFee
        );

        asset.forceApprove(burnerLoans, 0);
        _refund(asset, msg.sender, startingBalance);
    }

    /// @inheritdoc IBurnerLoansComposites
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

        IBurnerLoans.Position memory position = IBurnerLoansView(burnerLoans).getPosition(
            params_.asset,
            msg.sender
        );
        result.repaidOhm = params_.maxRepayOhm < position.debtOhm
            ? params_.maxRepayOhm
            : position.debtOhm;

        IERC20 ohmToken = IERC20(ohm);
        uint256 startingOhmBalance = ohmToken.balanceOf(address(this));
        if (params_.maxRepayOhm != 0) {
            ohmToken.safeTransferFrom(msg.sender, address(this), params_.maxRepayOhm);
        }
        if (result.repaidOhm != 0) {
            ohmToken.forceApprove(burnerLoans, result.repaidOhm);
            (, result.healthFactor) = IBurnerLoansLifecycle(burnerLoans).repay(
                params_.asset,
                uint128(result.repaidOhm),
                msg.sender
            );
            ohmToken.forceApprove(burnerLoans, 0);
        }

        if (params_.collateralAmount != 0) {
            (
                result.tokenOut,
                result.amountOut,
                result.remainingCollateral,
                result.healthFactor
            ) = IBurnerLoansLifecycle(burnerLoans).withdrawCollateral(
                params_.asset,
                params_.collateralAmount,
                msg.sender,
                params_.recipient
            );
        } else {
            result.remainingCollateral = position.depositedCollateral;
            if (position.debtOhm == 0) result.healthFactor = type(uint256).max;
        }

        result.refundedOhm = _refund(ohmToken, msg.sender, startingOhmBalance);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId_) public view override returns (bool) {
        return
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
        IOperatorAuth(burnerLoans).setAuthorizationWithSig(authorization_, signature_);
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
}
