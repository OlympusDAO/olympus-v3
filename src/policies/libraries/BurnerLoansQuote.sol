// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {BurnerLoansCalculator} from "src/policies/libraries/BurnerLoansCalculator.sol";
import {BurnerLoansMarketConfig} from "src/policies/libraries/BurnerLoansMarketConfig.sol";

/// @title Burner Loans Quote Library
/// @notice Shared pricing and health validation for Burner Loans previews and execution.
/// @dev Separately linked to keep the policy below EIP-170 without duplicating module state.
library BurnerLoansQuote {
    uint256 internal constant _WAD = 1e18;

    struct Pricing {
        uint256 ohmUsdPrice;
        uint256 backingPerOhmUsd;
        uint256 collateralUsdPrice;
        uint256 riskAdjustedCollateralUsd;
    }

    struct Dependencies {
        IERC20 ohm;
        uint8 ohmDecimals;
        address facility;
        uint128 globalDebtCapOhm;
        address backingOracle;
        IFLOANv1 floan;
        IPRICEv2 price;
    }

    function quoteBorrow(
        Dependencies memory dependencies_,
        address asset_,
        uint128 ohmAmount_,
        IFLOANv1.Position memory position
    ) public view returns (IBurnerLoans.BorrowPreview memory) {
        (uint32 marketId, IBurnerLoans.AssetConfig memory config) = _requireAssetEnabled(
            dependencies_.floan,
            dependencies_.facility,
            address(dependencies_.ohm),
            asset_
        );
        if (ohmAmount_ == 0) revert IBurnerLoans.BurnerLoans_ZeroAmount();

        if (position.collateral == 0) revert IBurnerLoans.BurnerLoans_NoCollateral();
        if (position.principalDue != 0 && block.timestamp >= position.maturity) {
            revert IBurnerLoans.BurnerLoans_PositionMatured(position.maturity);
        }

        uint256 assetDebt = _validateCaps(
            dependencies_.floan,
            dependencies_.facility,
            address(dependencies_.ohm),
            dependencies_.globalDebtCapOhm,
            asset_,
            marketId,
            ohmAmount_,
            config.debtCap
        );
        Pricing memory pricing = _pricing(
            dependencies_.ohm,
            dependencies_.backingOracle,
            dependencies_.price,
            asset_,
            position.collateral,
            config
        );
        if (position.principalDue != 0) {
            uint256 currentHealth = _health(
                dependencies_.ohmDecimals,
                position.principalDue,
                pricing,
                config
            );
            if (currentHealth < _WAD) {
                revert IBurnerLoans.BurnerLoans_UnhealthyPosition(currentHealth);
            }
        }

        uint128 resultingDebt = position.principalDue + ohmAmount_;
        uint256 resultingHealth = _health(
            dependencies_.ohmDecimals,
            resultingDebt,
            pricing,
            config
        );
        if (resultingHealth < _WAD) {
            revert IBurnerLoans.BurnerLoans_UnhealthyBorrow(resultingHealth);
        }

        return
            IBurnerLoans.BorrowPreview({
                fee: _borrowFee(
                    dependencies_.ohmDecimals,
                    dependencies_.floan,
                    marketId,
                    ohmAmount_,
                    assetDebt,
                    pricing,
                    config
                ),
                resultingDebtOhm: resultingDebt,
                resultingHealthFactor: resultingHealth,
                maturity: position.principalDue == 0
                    ? uint48(block.timestamp + config.termLength)
                    : position.maturity,
                executable: true
            });
    }

    function positionHealthFactor(
        Dependencies memory dependencies_,
        address asset_,
        uint256 collateral_,
        uint256 debtOhm_
    ) public view returns (uint256) {
        if (debtOhm_ == 0) return type(uint256).max;
        (, IBurnerLoans.AssetConfig memory config) = _requireAssetConfigured(
            dependencies_.floan,
            dependencies_.facility,
            address(dependencies_.ohm),
            asset_
        );
        return
            _health(
                dependencies_.ohmDecimals,
                debtOhm_,
                _pricing(
                    dependencies_.ohm,
                    dependencies_.backingOracle,
                    dependencies_.price,
                    asset_,
                    collateral_,
                    config
                ),
                config
            );
    }

    function _validateCaps(
        IFLOANv1 floan_,
        address facility_,
        address debtToken_,
        uint128 globalCap_,
        address asset_,
        uint32 marketId_,
        uint128 ohmAmount_,
        uint256 assetCap_
    ) private view returns (uint256 assetDebt) {
        uint256 totalDebt = floan_.facilityPrincipalDue(facility_, debtToken_);
        uint256 globalRoom = totalDebt <= globalCap_ ? globalCap_ - totalDebt : 0;
        if (ohmAmount_ > globalRoom) {
            revert IBurnerLoans.BurnerLoans_GlobalDebtCapExceeded(ohmAmount_, globalRoom);
        }

        assetDebt = floan_.marketPrincipalDue(marketId_);
        uint256 assetRoom = assetDebt <= assetCap_ ? assetCap_ - assetDebt : 0;
        if (ohmAmount_ > assetRoom) {
            revert IBurnerLoans.BurnerLoans_AssetDebtCapExceeded(asset_, ohmAmount_, assetRoom);
        }
    }

    function _pricing(
        IERC20 ohm_,
        address backingOracle_,
        IPRICEv2 price_,
        address asset_,
        uint256 collateral_,
        IBurnerLoans.AssetConfig memory config_
    ) private view returns (Pricing memory pricing) {
        uint48 frequency = price_.observationFrequency();
        pricing.ohmUsdPrice = _freshPrice(price_, address(ohm_), frequency);
        pricing.backingPerOhmUsd = _backingPerOhmUsd(backingOracle_, price_);
        pricing.collateralUsdPrice = _freshPrice(price_, asset_, frequency);
        pricing.riskAdjustedCollateralUsd = BurnerLoansCalculator.riskAdjustedCollateralUsd(
            BurnerLoansCalculator.collateralValueUsd(
                collateral_,
                pricing.collateralUsdPrice,
                config_.collateralDecimals
            ),
            config_.collateralFactorBps
        );
    }

    function _health(
        uint8 ohmDecimals_,
        uint256 debtOhm_,
        Pricing memory pricing_,
        IBurnerLoans.AssetConfig memory config_
    ) private pure returns (uint256) {
        uint256 debtValueUsd = BurnerLoansCalculator.debtValueUsd(
            debtOhm_,
            pricing_.ohmUsdPrice,
            ohmDecimals_
        );
        uint256 requiredUsd = BurnerLoansCalculator.requiredCollateralUsd(
            debtValueUsd,
            debtOhm_,
            pricing_.backingPerOhmUsd,
            ohmDecimals_,
            config_.minCollateralRatioBps,
            config_.backingMultiplierBps
        );
        return BurnerLoansCalculator.healthFactor(pricing_.riskAdjustedCollateralUsd, requiredUsd);
    }

    function _borrowFee(
        uint8 ohmDecimals_,
        IFLOANv1 floan_,
        uint32 marketId_,
        uint128 ohmAmount_,
        uint256 assetDebt_,
        Pricing memory pricing_,
        IBurnerLoans.AssetConfig memory config_
    ) private view returns (uint256) {
        uint256 debtValueUsd = BurnerLoansCalculator.debtValueUsd(
            ohmAmount_,
            pricing_.ohmUsdPrice,
            ohmDecimals_
        );
        uint256 requiredUsd = BurnerLoansCalculator.requiredCollateralUsd(
            debtValueUsd,
            ohmAmount_,
            pricing_.backingPerOhmUsd,
            ohmDecimals_,
            config_.minCollateralRatioBps,
            config_.backingMultiplierBps
        );
        uint256 requiredAsset = BurnerLoansCalculator.requiredCollateralAsset(
            requiredUsd,
            pricing_.collateralUsdPrice,
            config_.collateralDecimals
        );
        uint256 utilization = BurnerLoansCalculator.assetUtilizationWad(
            assetDebt_,
            config_.debtCap
        );
        if (utilization == type(uint256).max || utilization > _WAD) {
            revert IBurnerLoans.BurnerLoans_InvalidCap();
        }
        IBurnerLoans.AssetFeeConfig memory feeConfig = BurnerLoansMarketConfig.feeConfig(
            floan_.getMarket(marketId_),
            floan_.getMarketConfigData(marketId_)
        );
        uint256 feeRate = BurnerLoansCalculator.feeRateWad(
            utilization,
            feeConfig.baseFeeBps,
            feeConfig.kinkBps,
            feeConfig.preKinkSlopeBps,
            feeConfig.postKinkSlopeBps
        );
        return BurnerLoansCalculator.borrowFee(requiredAsset, feeRate);
    }

    function _freshPrice(
        IPRICEv2 price_,
        address asset_,
        uint48 frequency_
    ) private view returns (uint256 price) {
        uint48 timestamp;
        (price, timestamp) = price_.getPrice(asset_, IPRICEv2.Variant.CURRENT);
        if (
            price == 0 ||
            timestamp == 0 ||
            block.timestamp > uint256(timestamp) + uint256(frequency_)
        ) revert IBurnerLoans.BurnerLoans_InvalidPrice();
    }

    function _backingPerOhmUsd(address oracle_, IPRICEv2 price_) private view returns (uint256) {
        if (oracle_ == address(0)) revert IBurnerLoans.BurnerLoans_ZeroAddress();
        uint256 backing18 = IOlympusBackingOracle(oracle_).backing();
        if (backing18 == 0) revert IBurnerLoans.BurnerLoans_InvalidPrice();
        return FullMath.mulDivUp(backing18, BurnerLoansCalculator.scale(price_.decimals()), _WAD);
    }

    function _requireAssetConfigured(
        IFLOANv1 floan_,
        address facility_,
        address debtToken_,
        address asset_
    ) private view returns (uint32 marketId_, IBurnerLoans.AssetConfig memory config) {
        bool exists;
        (exists, marketId_) = floan_.getMarketId(facility_, asset_, debtToken_);
        if (!exists) {
            revert IBurnerLoans.BurnerLoans_AssetNotConfigured(asset_);
        }
        IFLOANv1.Market memory market = floan_.getMarket(marketId_);
        if (market.configId != BurnerLoansMarketConfig.CONFIG_ID) {
            revert IBurnerLoans.BurnerLoans_AssetNotConfigured(asset_);
        }
        config = BurnerLoansMarketConfig.assetConfig(market, floan_.getMarketConfigData(marketId_));
    }

    function _requireAssetEnabled(
        IFLOANv1 floan_,
        address facility_,
        address debtToken_,
        address asset_
    ) private view returns (uint32 marketId_, IBurnerLoans.AssetConfig memory config) {
        (marketId_, config) = _requireAssetConfigured(floan_, facility_, debtToken_, asset_);
        if (!config.enabled) revert IBurnerLoans.BurnerLoans_AssetNotEnabled(asset_);
    }
}
