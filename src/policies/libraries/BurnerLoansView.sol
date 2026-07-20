// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansCustody} from "src/policies/libraries/BurnerLoansCustody.sol";
import {BurnerLoansQuote} from "src/policies/libraries/BurnerLoansQuote.sol";
import {BurnerLoansMarketConfig} from "src/policies/libraries/BurnerLoansMarketConfig.sol";

/// @title Burner Loans View Library
/// @notice Separately linked position and custody previews exposed by the lifecycle policy.
library BurnerLoansView {
    uint256 internal constant _WAD = 1e18;

    struct Dependencies {
        IERC20 ohm;
        uint8 ohmDecimals;
        IDepositManager depositManager;
        address facility;
        uint128 globalDebtCapOhm;
        address backingOracle;
        IFLOANv1 floan;
        IPRICEv2 price;
    }

    function getPosition(
        IFLOANv1.Position memory position
    ) public pure returns (IBurnerLoans.Position memory) {
        return
            IBurnerLoans.Position({
                depositedCollateral: position.collateral,
                debtOhm: position.principalDue,
                maturity: position.maturity,
                lastBorrowBlock: position.lastBorrowBlock,
                status: position.principalDue == 0
                    ? IBurnerLoans.PositionStatus.NoDebt
                    : IBurnerLoans.PositionStatus.Active
            });
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
        return floan_.marketPrincipalDue(uint32(marketIds[0]));
    }

    function previewDepositCollateral(
        Dependencies memory dependencies_,
        address asset_,
        uint128 amount_,
        IFLOANv1.Position memory position
    ) public view returns (uint256 depositedCollateral, uint256 totalCollateral) {
        IBurnerLoans.AssetConfig memory config = _requireAssetConfigured(dependencies_, asset_);
        if (!config.enabled) revert IBurnerLoans.BurnerLoans_AssetNotEnabled(asset_);
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

    function previewWithdrawCollateral(
        Dependencies memory dependencies_,
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
            _quoteDependencies(dependencies_),
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

    function _quoteDependencies(
        Dependencies memory dependencies_
    ) private pure returns (BurnerLoansQuote.Dependencies memory) {
        return
            BurnerLoansQuote.Dependencies({
                ohm: dependencies_.ohm,
                ohmDecimals: dependencies_.ohmDecimals,
                facility: dependencies_.facility,
                globalDebtCapOhm: dependencies_.globalDebtCapOhm,
                backingOracle: dependencies_.backingOracle,
                floan: dependencies_.floan,
                price: dependencies_.price
            });
    }

    function _requireAssetConfigured(
        Dependencies memory dependencies_,
        address asset_
    ) private view returns (IBurnerLoans.AssetConfig memory config) {
        uint32 marketId_ = BurnerLoansMarketConfig.marketId(
            dependencies_.floan,
            dependencies_.facility,
            asset_,
            address(dependencies_.ohm)
        );
        IFLOANv1.Market memory market = dependencies_.floan.getMarket(marketId_);
        if (market.configId != BurnerLoansMarketConfig.CONFIG_ID) {
            revert IBurnerLoans.BurnerLoans_AssetNotConfigured(asset_);
        }
        return
            BurnerLoansMarketConfig.assetConfig(
                market,
                dependencies_.floan.getMarketConfigData(marketId_)
            );
    }
}
