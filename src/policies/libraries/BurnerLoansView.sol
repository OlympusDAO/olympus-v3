// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansContext} from "src/policies/interfaces/IBurnerLoansSeizureContext.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansCustody} from "src/policies/libraries/BurnerLoansCustody.sol";
import {BurnerLoansQuote} from "src/policies/libraries/BurnerLoansQuote.sol";
import {BurnerLoansMarketConfig} from "src/policies/libraries/BurnerLoansMarketConfig.sol";
import {BurnerLoansPositions} from "src/policies/libraries/BurnerLoansPositions.sol";

/// @title Burner Loans View Library
/// @notice Separately linked position and custody previews exposed by the lifecycle policy.
library BurnerLoansView {
    uint256 internal constant _WAD = 1e18;

    function getPosition(
        IFLOANv1.Position memory position
    ) public pure returns (IBurnerLoans.Position memory) {
        return
            IBurnerLoans.Position({
                depositedCollateral: position.collateral,
                debtOhm: position.principalDue,
                maturity: position.maturity,
                lastBorrowBlock: position.lastBorrowBlock,
                status: position.defaulted
                    ? IBurnerLoans.PositionStatus.Seized
                    : position.principalDue == 0
                    ? IBurnerLoans.PositionStatus.NoDebt
                    : IBurnerLoans.PositionStatus.Active
            });
    }

    function getPositionForBorrower(
        IFLOANv1 floan_,
        uint32 marketId_,
        address borrower_
    ) public view returns (IBurnerLoans.Position memory) {
        return getPosition(BurnerLoansPositions.getOrEmpty(floan_, marketId_, borrower_));
    }

    function isBorrowerSeizable(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint32 marketId_,
        address borrower_
    ) public view returns (bool) {
        return
            isSeizable(
                dependencies_,
                asset_,
                BurnerLoansPositions.getOrEmpty(dependencies_.floan, marketId_, borrower_)
            );
    }

    function isSeizable(
        BurnerLoansContext memory dependencies_,
        address asset_,
        IFLOANv1.Position memory position
    ) public view returns (bool) {
        _requireAssetConfigured(dependencies_, asset_);
        if (position.principalDue == 0 || position.defaulted) return false;
        if (block.timestamp >= position.maturity) return true;
        return
            BurnerLoansQuote.positionHealthFactor(
                dependencies_,
                asset_,
                position.collateral,
                position.principalDue
            ) < _WAD;
    }

    function assetActiveDebtOhm(
        IFLOANv1 floan_,
        address facility_,
        address debtToken_,
        address asset_
    ) public view returns (uint256) {
        uint256[] memory marketIds = floan_.getMarketIds(facility_, asset_, debtToken_);
        if (marketIds.length == 0) return 0;
        if (marketIds.length != 1) {
            revert IBurnerLoans.BurnerLoans_AmbiguousMarket(asset_, marketIds.length);
        }
        return floan_.getMarketPrincipalDue(uint32(marketIds[0]));
    }

    function previewDepositCollateral(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint128 amount_,
        IFLOANv1.Position memory position
    ) public view returns (uint256 depositedCollateral, uint256 totalCollateral) {
        IBurnerLoans.AssetConfig memory config = _requireAssetConfigured(dependencies_, asset_);
        if (!config.originationsEnabled)
            revert IBurnerLoans.BurnerLoans_AssetOriginationsDisabled(asset_);
        if (amount_ == 0) revert IBurnerLoans.BurnerLoans_ZeroAmount();

        IDepositManager.AssetConfiguration memory assetConfiguration = BurnerLoansCustody
            .validateCustodySupport(
                dependencies_.depositManager,
                asset_,
                BurnerLoansConstants.DEPOSIT_PERIOD,
                true
            );
        BurnerLoansCustody.validateDepositAmount(
            dependencies_.depositManager,
            asset_,
            assetConfiguration,
            amount_
        );
        depositedCollateral = BurnerLoansCustody.previewDepositAmount(
            assetConfiguration.vault,
            amount_
        );
        if (depositedCollateral == 0) {
            revert IBurnerLoans.BurnerLoans_ZeroCollateralCredit();
        }
        totalCollateral = position.collateral + depositedCollateral;
    }

    function previewDepositCollateralForBorrower(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint128 amount_,
        uint32 marketId_,
        address borrower_
    ) public view returns (uint256 depositedCollateral, uint256 totalCollateral) {
        return
            previewDepositCollateral(
                dependencies_,
                asset_,
                amount_,
                BurnerLoansPositions.getOrEmpty(dependencies_.floan, marketId_, borrower_)
            );
    }

    function previewRepay(
        uint128 repayOhm_,
        IFLOANv1.Position memory position
    ) public view returns (IBurnerLoans.RepayPreview memory preview) {
        uint256 debtOhm = position.principalDue;
        if (debtOhm == 0) revert IBurnerLoans.BurnerLoans_NoDebt();
        if (repayOhm_ > debtOhm) {
            revert IBurnerLoans.BurnerLoans_RepayExceedsDebt(repayOhm_, debtOhm);
        }
        if (block.number <= position.lastBorrowBlock) {
            revert IBurnerLoans.BurnerLoans_SameBlockRepay(position.lastBorrowBlock);
        }

        uint256 remainingDebtOhm = debtOhm - repayOhm_;
        preview = IBurnerLoans.RepayPreview({
            repayAmount: repayOhm_,
            remainingDebtOhm: remainingDebtOhm,
            resultingHealthFactor: remainingDebtOhm == 0 ? type(uint256).max : 0,
            executable: true
        });
    }

    function previewRepayForBorrower(
        IFLOANv1 floan_,
        uint32 marketId_,
        address borrower_,
        uint128 repayOhm_
    ) public view returns (IBurnerLoans.RepayPreview memory) {
        return
            previewRepay(repayOhm_, BurnerLoansPositions.getOrEmpty(floan_, marketId_, borrower_));
    }

    function previewWithdrawCollateral(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint128 amount_,
        IFLOANv1.Position memory position
    ) public view returns (IBurnerLoans.WithdrawPreview memory) {
        _requireAssetConfigured(dependencies_, asset_);
        if (amount_ == 0) revert IBurnerLoans.BurnerLoans_ZeroAmount();

        IDepositManager.AssetConfiguration memory assetConfiguration = BurnerLoansCustody
            .validateCustodySupport(
                dependencies_.depositManager,
                asset_,
                BurnerLoansConstants.DEPOSIT_PERIOD,
                false
            );
        if (amount_ > position.collateral) {
            revert IBurnerLoans.BurnerLoans_InsufficientCollateral(amount_, position.collateral);
        }

        uint256 remainingCollateral = position.collateral - amount_;
        uint256 resultingHealthFactor = BurnerLoansQuote.positionHealthFactor(
            dependencies_,
            asset_,
            remainingCollateral,
            position.principalDue
        );
        uint256 returnAmount = BurnerLoansCustody.previewWithdrawAmount(
            assetConfiguration.vault,
            amount_
        );
        return
            IBurnerLoans.WithdrawPreview({
                returnToken: asset_,
                returnAmount: returnAmount,
                remainingDepositedCollateral: remainingCollateral,
                resultingHealthFactor: resultingHealthFactor,
                executable: returnAmount != 0 &&
                    (position.principalDue == 0 || resultingHealthFactor >= _WAD)
            });
    }

    function previewWithdrawCollateralForBorrower(
        BurnerLoansContext memory dependencies_,
        address asset_,
        uint128 amount_,
        uint32 marketId_,
        address borrower_
    ) public view returns (IBurnerLoans.WithdrawPreview memory) {
        return
            previewWithdrawCollateral(
                dependencies_,
                asset_,
                amount_,
                BurnerLoansPositions.getOrEmpty(dependencies_.floan, marketId_, borrower_)
            );
    }

    function _requireAssetConfigured(
        BurnerLoansContext memory dependencies_,
        address asset_
    ) private view returns (IBurnerLoans.AssetConfig memory config) {
        uint32 marketId_ = BurnerLoansMarketConfig.marketId(
            dependencies_.floan,
            dependencies_.facility,
            asset_,
            address(dependencies_.ohm)
        );
        IFLOANv1.Market memory market = dependencies_.floan.getMarket(marketId_);
        return
            BurnerLoansMarketConfig.assetConfig(
                marketId_,
                market,
                dependencies_.floan.getMarketConfigData(marketId_)
            );
    }
}
