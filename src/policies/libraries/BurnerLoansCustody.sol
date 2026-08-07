// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansCustodyAccounting} from "src/policies/libraries/BurnerLoansCustodyAccounting.sol";
import {BurnerLoansQuote} from "src/policies/libraries/BurnerLoansQuote.sol";
import {BurnerLoansPositions} from "src/policies/libraries/BurnerLoansPositions.sol";

/// @title Burner Loans Custody Library
/// @notice Separately linked DepositManager operations executed in the lifecycle's context.
/// @dev Library delegatecalls preserve BurnerLoans as the DepositManager operator and receipt holder.
library BurnerLoansCustody {
    using TransferHelper for ERC20;

    /// @dev Fixed-point scale used for withdrawal health validation.
    uint256 private constant _WAD = 1e18;

    /// @notice Parameters for executing a borrow.
    struct BorrowParams {
        uint32 marketId;
        address asset;
        address onBehalfOf;
        address recipient;
        uint128 ohmAmount;
        uint256 maxFee;
    }

    /// @notice Parameters for executing a collateral withdrawal.
    struct WithdrawParams {
        uint32 marketId;
        address asset;
        address onBehalfOf;
        address recipient;
        uint128 amount;
    }

    /// @notice Quotes and executes a borrow against the first borrower position.
    /// @dev Reverts on quote validation failure, excessive fees, transfer failure, or FLOAN/MINTR
    ///      mutation failure.
    /// @param dependencies_ Burner Loans dependency context.
    /// @param mintr_ MINTR module used to mint debt.
    /// @param treasury_ Treasury receiving collateral-denominated fees.
    /// @param params_ Borrow execution parameters.
    /// @return preview Executed borrow quote.
    function borrow(
        BurnerLoansContext memory dependencies_,
        MINTRv1 mintr_,
        TRSRYv1 treasury_,
        BorrowParams memory params_
    ) public returns (IBurnerLoans.BorrowPreview memory preview) {
        preview = BurnerLoansQuote.quoteBorrow(
            dependencies_,
            params_.asset,
            params_.ohmAmount,
            BurnerLoansPositions.getOrEmpty(
                dependencies_.floan,
                params_.marketId,
                params_.onBehalfOf
            )
        );
        if (preview.fee > params_.maxFee) {
            revert IBurnerLoans.BurnerLoans_FeeExceedsMax(preview.fee, params_.maxFee);
        }

        (, uint64 positionId) = BurnerLoansPositions.find(
            dependencies_.floan,
            params_.marketId,
            params_.onBehalfOf
        );
        dependencies_.floan.increaseDebt(positionId, params_.ohmAmount, 0, preview.maturity);
        if (preview.fee != 0) {
            ERC20(params_.asset).safeTransferFrom(msg.sender, address(treasury_), preview.fee);
        }
        mintr_.mintOhm(params_.recipient, params_.ohmAmount);

        emit IBurnerLoans.Borrowed(
            msg.sender,
            params_.asset,
            params_.onBehalfOf,
            params_.recipient,
            params_.ohmAmount,
            preview.fee
        );
    }

    /// @notice Deposits collateral into custody and credits the borrower position.
    /// @dev Reverts when custody is unsupported, limits are exceeded, DepositManager observes an
    ///      inexact transfer, credit rounds to zero, or FLOAN rejects the position mutation.
    /// @return depositedCollateral Actual collateral credited after vault rounding.
    /// @return totalCollateral Resulting position collateral.
    function depositCollateral(
        IFLOANv1 floan_,
        IDepositManager depositManager_,
        uint32 marketId_,
        address asset_,
        uint128 amount_,
        address onBehalfOf_
    ) public returns (uint256 depositedCollateral, uint256 totalCollateral) {
        IDepositManager.AssetConfiguration memory assetConfiguration = validateCustodySupport(
            depositManager_,
            asset_,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            true
        );
        validateDepositAmount(depositManager_, asset_, assetConfiguration, amount_);

        uint128 depositedCollateral_ = deposit(
            depositManager_,
            asset_,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            amount_
        );
        if (depositedCollateral_ == 0) revert IBurnerLoans.BurnerLoans_ZeroCollateralCredit();
        uint64 positionId = BurnerLoansPositions.getOrCreate(floan_, marketId_, onBehalfOf_);
        uint128 totalCollateral_ = floan_.addCollateral(positionId, depositedCollateral_);

        emit IBurnerLoans.CollateralDeposited(
            msg.sender,
            asset_,
            onBehalfOf_,
            amount_,
            depositedCollateral_
        );
        return (depositedCollateral_, totalCollateral_);
    }

    /// @notice Validates and executes a collateral withdrawal.
    /// @dev Reverts for invalid inputs, unsupported custody, insufficient or unhealthy collateral,
    ///      zero vault output, or an underlying mutation failure.
    /// @return tokenOut Collateral token returned.
    /// @return amountOut Actual amount returned after vault conversion.
    /// @return remainingCollateral Resulting credited collateral.
    /// @return healthFactor Resulting position health factor.
    function withdrawCollateral(
        BurnerLoansContext memory dependencies_,
        IDepositManager depositManager_,
        WithdrawParams memory params_
    )
        public
        returns (
            address tokenOut,
            uint256 amountOut,
            uint256 remainingCollateral,
            uint256 healthFactor
        )
    {
        if (params_.amount == 0) revert IBurnerLoans.BurnerLoans_ZeroAmount();
        if (params_.recipient == address(0)) revert IBurnerLoans.BurnerLoans_ZeroAddress();
        IDepositManager.AssetConfiguration memory assetConfiguration = validateCustodySupport(
            depositManager_,
            params_.asset,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            false
        );
        if (previewWithdrawAmount(assetConfiguration.vault, params_.amount) == 0) {
            revert IBurnerLoans.BurnerLoans_ZeroCollateralWithdrawal();
        }

        IFLOANv1.Position memory position = BurnerLoansPositions.getOrEmpty(
            dependencies_.floan,
            params_.marketId,
            params_.onBehalfOf
        );
        if (params_.amount > position.collateral) {
            revert IBurnerLoans.BurnerLoans_InsufficientCollateral(
                params_.amount,
                position.collateral
            );
        }
        remainingCollateral = position.collateral - params_.amount;
        healthFactor = BurnerLoansQuote.positionHealthFactor(
            dependencies_,
            params_.asset,
            remainingCollateral,
            position.principalDue
        );
        if (position.principalDue != 0 && healthFactor < _WAD) {
            revert IBurnerLoans.BurnerLoans_UnhealthyWithdrawal(healthFactor);
        }

        (, uint64 positionId) = BurnerLoansPositions.find(
            dependencies_.floan,
            params_.marketId,
            params_.onBehalfOf
        );
        dependencies_.floan.removeCollateral(positionId, params_.amount);
        amountOut = withdraw(
            depositManager_,
            params_.asset,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            params_.amount,
            params_.recipient
        );
        if (amountOut == 0) revert IBurnerLoans.BurnerLoans_ZeroCollateralWithdrawal();

        emit IBurnerLoans.CollateralWithdrawn(
            msg.sender,
            params_.asset,
            params_.onBehalfOf,
            params_.recipient,
            params_.amount
        );
        tokenOut = params_.asset;
    }

    /// @notice Validates custody support for the calling Burner Loans policy.
    /// @dev Reverts with `BurnerLoans_InvalidDepositManager` when the manager, asset, or period is
    ///      unavailable.
    function validateCustodySupport(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        bool requireEnabledPeriod_
    ) public view returns (IDepositManager.AssetConfiguration memory assetConfiguration) {
        return
            validateCustodySupportFor(
                depositManager_,
                asset_,
                depositPeriod_,
                requireEnabledPeriod_,
                address(this)
            );
    }

    /// @notice Validates custody support for an explicit operator.
    /// @dev Reverts with `BurnerLoans_InvalidDepositManager` when the manager, asset, or period is
    ///      unavailable.
    function validateCustodySupportFor(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        bool requireEnabledPeriod_,
        address operator_
    ) public view returns (IDepositManager.AssetConfiguration memory assetConfiguration) {
        try IEnabler(address(depositManager_)).isEnabled() returns (bool enabled) {
            if (!enabled) {
                revert IBurnerLoans.BurnerLoans_InvalidDepositManager(address(depositManager_));
            }
        } catch {
            revert IBurnerLoans.BurnerLoans_InvalidDepositManager(address(depositManager_));
        }

        assetConfiguration = depositManager_.getAssetConfiguration(IERC20(asset_));
        if (!assetConfiguration.isConfigured) {
            revert IBurnerLoans.BurnerLoans_InvalidDepositManager(address(depositManager_));
        }

        IDepositManager.AssetPeriodStatus memory assetPeriod = depositManager_.isAssetPeriod(
            IERC20(asset_),
            depositPeriod_,
            operator_
        );
        if (!assetPeriod.isConfigured || (requireEnabledPeriod_ && !assetPeriod.isEnabled)) {
            revert IBurnerLoans.BurnerLoans_InvalidDepositManager(address(depositManager_));
        }
    }

    /// @notice Validates a deposit amount for the calling Burner Loans policy.
    /// @dev Reverts when the amount is below the minimum or would exceed the operator deposit cap.
    function validateDepositAmount(
        IDepositManager depositManager_,
        address asset_,
        IDepositManager.AssetConfiguration memory assetConfiguration_,
        uint128 amount_
    ) public view {
        validateDepositAmountFor(
            depositManager_,
            asset_,
            assetConfiguration_,
            amount_,
            address(this)
        );
    }

    /// @notice Validates a deposit amount for an explicit operator.
    /// @dev Reverts when the amount is below the minimum or would exceed the operator deposit cap.
    function validateDepositAmountFor(
        IDepositManager depositManager_,
        address asset_,
        IDepositManager.AssetConfiguration memory assetConfiguration_,
        uint128 amount_,
        address operator_
    ) public view {
        if (amount_ < assetConfiguration_.minimumDeposit) {
            revert IAssetManager.AssetManager_MinimumDepositNotMet(
                asset_,
                amount_,
                assetConfiguration_.minimumDeposit
            );
        }

        (, uint256 assetAmountBefore) = depositManager_.getOperatorAssets(
            IERC20(asset_),
            operator_
        );
        if (assetAmountBefore + amount_ > assetConfiguration_.depositCap) {
            revert IAssetManager.AssetManager_DepositCapExceeded(
                asset_,
                assetAmountBefore,
                assetConfiguration_.depositCap
            );
        }
    }

    /// @notice Quotes withdrawable collateral credited by a vault deposit.
    /// @param vault_ ERC-4626 vault, or zero for direct custody.
    /// @param amount_ Underlying amount supplied.
    /// @return Actual withdrawable credit, rounded according to the vault.
    function previewDepositAmount(address vault_, uint128 amount_) public view returns (uint128) {
        if (vault_ == address(0)) return amount_;
        IERC4626 vault = IERC4626(vault_);
        uint256 shares = vault.previewDeposit(amount_);
        return shares == 0 ? 0 : SafeCast.toUint128(vault.previewRedeem(shares));
    }

    /// @notice Quotes vault assets returned for a requested collateral debit.
    /// @param vault_ ERC-4626 vault, or zero for direct custody.
    /// @param amount_ Credited collateral amount.
    /// @return Actual underlying amount returned by the vault.
    function previewWithdrawAmount(address vault_, uint256 amount_) public view returns (uint256) {
        if (vault_ == address(0)) return amount_;
        IERC4626 vault = IERC4626(vault_);
        return vault.previewRedeem(vault.convertToShares(amount_));
    }

    /// @notice Transfers collateral into DepositManager custody.
    /// @dev Reverts on safe-transfer failure, DepositManager's exact-receipt rejection, residual
    ///      collateral, receipt approval failure, or another DepositManager error.
    /// @return depositedCollateral Actual collateral credited after vault rounding.
    function deposit(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        uint128 amount_
    ) public returns (uint128 depositedCollateral) {
        ERC20 asset = ERC20(asset_);
        uint256 startingBalance = IERC20(asset_).balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount_);
        asset.safeApprove(address(depositManager_), amount_);

        uint256 depositedCollateralRaw;
        (, depositedCollateralRaw) = depositManager_.deposit(
            IDepositManager.DepositParams({
                asset: IERC20(asset_),
                depositPeriod: depositPeriod_,
                depositor: address(this),
                amount: amount_,
                shouldWrap: false
            })
        );
        depositedCollateral = SafeCast.toUint128(depositedCollateralRaw);

        uint256 residualBalance = IERC20(asset_).balanceOf(address(this));
        if (residualBalance > startingBalance) {
            revert IBurnerLoans.BurnerLoans_ResidualCollateralBalance(
                asset_,
                residualBalance - startingBalance
            );
        }
        _approveReceiptBurn(depositManager_, asset_, depositPeriod_);
    }

    /// @notice Withdraws collateral from DepositManager custody.
    /// @dev Reverts with the underlying DepositManager error when withdrawal is unavailable.
    /// @return Actual amount transferred to the recipient.
    function withdraw(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_,
        uint256 amount_,
        address recipient_
    ) public returns (uint256) {
        return
            depositManager_.withdraw(
                IDepositManager.WithdrawParams({
                    asset: IERC20(asset_),
                    depositPeriod: depositPeriod_,
                    depositor: address(this),
                    recipient: recipient_,
                    amount: amount_,
                    isWrapped: false
                })
            );
    }

    /// @notice Returns validated custody accounting for an asset and operator.
    /// @dev Reverts when custody support is invalid.
    function getAssetCollateralStatus(
        IDepositManager depositManager_,
        address asset_,
        address operator_
    ) public view returns (IBurnerLoans.AssetCollateralStatus memory) {
        validateCustodySupportFor(
            depositManager_,
            asset_,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            false,
            operator_
        );
        return BurnerLoansCustodyAccounting.status(depositManager_, asset_, operator_);
    }

    /// @notice Claims solvent custody yield to a recipient.
    /// @dev Returns zero when no yield is claimable and reverts when custody is unsupported or
    ///      insolvent.
    /// @return claimed Actual yield transferred.
    function harvestYield(
        IDepositManager depositManager_,
        address asset_,
        address operator_,
        address recipient_
    ) public returns (uint256 claimed) {
        validateCustodySupportFor(
            depositManager_,
            asset_,
            BurnerLoansConstants.DEPOSIT_PERIOD,
            false,
            operator_
        );
        IBurnerLoans.AssetCollateralStatus memory collateralStatus = BurnerLoansCustodyAccounting
            .status(depositManager_, asset_, operator_);
        if (!collateralStatus.solvent) {
            revert IBurnerLoans.BurnerLoans_CustodyShortfall(
                asset_,
                collateralStatus.liabilities,
                collateralStatus.assets,
                collateralStatus.borrowed
            );
        }
        if (collateralStatus.claimableYield == 0) return 0;

        claimed = depositManager_.claimYield(
            IERC20(asset_),
            recipient_,
            collateralStatus.claimableYield
        );
        emit IBurnerLoans.YieldHarvested(asset_, claimed);
    }

    /// @notice Reconciles MINTR approval to unused global debt capacity.
    /// @dev Increases or decreases approval by the exact delta from the current allowance.
    /// @return desiredApproval Remaining mint capacity after active principal.
    function reconcileMintApproval(
        IFLOANv1 floan_,
        MINTRv1 mintr_,
        IERC20 ohm_,
        uint128 debtCapOhm_
    ) public returns (uint256 desiredApproval) {
        uint256 activePrincipal = floan_.getFacilityPrincipalDue(address(this), address(ohm_));
        desiredApproval = debtCapOhm_ > activePrincipal ? debtCapOhm_ - activePrincipal : 0;
        uint256 currentApproval = mintr_.mintApproval(address(this));
        if (desiredApproval > currentApproval) {
            mintr_.increaseMintApproval(address(this), desiredApproval - currentApproval);
        } else if (desiredApproval < currentApproval) {
            mintr_.decreaseMintApproval(address(this), currentApproval - desiredApproval);
        }
    }

    /// @notice Repays principal, burns OHM, and restores equivalent MINTR capacity.
    /// @dev Reverts for a missing/debt-free position, excessive or same-block repayment, token
    ///      transfer failure, or an underlying FLOAN/MINTR failure.
    /// @return healthFactor Max uint after full repayment, otherwise the conservative zero sentinel.
    function repay(
        IFLOANv1 floan_,
        MINTRv1 mintr_,
        IERC20 ohm_,
        uint32 marketId_,
        address asset_,
        address onBehalfOf_,
        uint128 repayOhm_
    ) public returns (uint256 healthFactor) {
        (bool exists, uint64 positionId) = BurnerLoansPositions.find(
            floan_,
            marketId_,
            onBehalfOf_
        );
        if (!exists) revert IBurnerLoans.BurnerLoans_NoCollateral();

        IFLOANv1.Position memory position = floan_.getPosition(positionId);
        uint256 debtOhm = position.principalDue;
        if (debtOhm == 0) revert IBurnerLoans.BurnerLoans_NoDebt();
        if (repayOhm_ > debtOhm) {
            revert IBurnerLoans.BurnerLoans_RepayExceedsDebt(repayOhm_, debtOhm);
        }
        if (block.number <= position.lastBorrowBlock) {
            revert IBurnerLoans.BurnerLoans_SameBlockRepay(position.lastBorrowBlock);
        }
        uint256 remainingDebtOhm = debtOhm - repayOhm_;

        floan_.decreaseDebt(positionId, repayOhm_, 0);
        ERC20(address(ohm_)).safeTransferFrom(msg.sender, address(this), repayOhm_);
        mintr_.burnOhm(address(this), repayOhm_);
        mintr_.increaseMintApproval(address(this), repayOhm_);

        emit IBurnerLoans.Repaid(msg.sender, asset_, onBehalfOf_, repayOhm_, remainingDebtOhm);
        return remainingDebtOhm == 0 ? type(uint256).max : 0;
    }

    /// @notice Quotes and executes a fixed-term maturity extension.
    /// @dev Reverts for a missing position, invalid quote, excessive fee, transfer failure, or an
    ///      underlying FLOAN mutation failure.
    /// @return preview Executed extension quote.
    function extend(
        BurnerLoansContext memory dependencies_,
        TRSRYv1 treasury_,
        uint32 marketId_,
        address asset_,
        address onBehalfOf_,
        uint16 termCount_,
        uint256 maxFee_
    ) public returns (IBurnerLoans.ExtendPreview memory preview) {
        (bool exists, uint64 positionId) = BurnerLoansPositions.find(
            dependencies_.floan,
            marketId_,
            onBehalfOf_
        );
        if (!exists) revert IBurnerLoans.BurnerLoans_NoCollateral();
        preview = BurnerLoansQuote.quoteExtend(
            dependencies_,
            asset_,
            termCount_,
            dependencies_.floan.getPosition(positionId)
        );
        if (preview.fee > maxFee_) {
            revert IBurnerLoans.BurnerLoans_FeeExceedsMax(preview.fee, maxFee_);
        }

        dependencies_.floan.extendMaturity(positionId, preview.maturity);
        if (preview.fee != 0) {
            ERC20(asset_).safeTransferFrom(msg.sender, address(treasury_), preview.fee);
        }

        emit IBurnerLoans.Extended(msg.sender, asset_, onBehalfOf_, preview.maturity, preview.fee);
    }

    function _approveReceiptBurn(
        IDepositManager depositManager_,
        address asset_,
        uint8 depositPeriod_
    ) private {
        IReceiptTokenManager receiptTokenManager = depositManager_.getReceiptTokenManager();
        if (address(receiptTokenManager) == address(0)) return;

        uint256 receiptTokenId = depositManager_.getReceiptTokenId(
            IERC20(asset_),
            depositPeriod_,
            address(this)
        );
        if (
            receiptTokenManager.allowance(
                address(this),
                address(depositManager_),
                receiptTokenId
            ) !=
            type(uint256).max &&
            !receiptTokenManager.approve(
                address(depositManager_),
                receiptTokenId,
                type(uint256).max
            )
        ) {
            revert IBurnerLoans.BurnerLoans_ReceiptApprovalFailed(address(receiptTokenManager));
        }
    }
}
