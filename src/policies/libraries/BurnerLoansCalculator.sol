// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

/// @title Burner Loans Calculator
/// @notice Separately linked scale-aware calculations used by Burner Loans lifecycle policies.
library BurnerLoansCalculator {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant WAD = 1e18;

    function scale(uint8 decimals_) public pure returns (uint256) {
        return 10 ** uint256(decimals_);
    }

    function debtValueUsd(
        uint256 debt_,
        uint256 debtUsdPrice_,
        uint8 debtDecimals_
    ) public pure returns (uint256) {
        return FullMath.mulDivUp(debt_, debtUsdPrice_, scale(debtDecimals_));
    }

    function collateralValueUsd(
        uint256 collateral_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) public pure returns (uint256) {
        return FullMath.mulDiv(collateral_, collateralUsdPrice_, scale(collateralDecimals_));
    }

    function riskAdjustedCollateralUsd(
        uint256 collateralValueUsd_,
        uint256 collateralFactorBps_
    ) public pure returns (uint256) {
        return FullMath.mulDiv(collateralValueUsd_, collateralFactorBps_, BPS);
    }

    function requiredBackingUsd(
        uint256 debt_,
        uint256 backingPerDebtUsd_,
        uint8 debtDecimals_,
        uint256 backingMultiplierBps_
    ) public pure returns (uint256) {
        return
            FullMath.mulDivUp(
                debtValueUsd(debt_, backingPerDebtUsd_, debtDecimals_),
                backingMultiplierBps_,
                BPS
            );
    }

    function requiredCollateralUsd(
        uint256 debtValueUsd_,
        uint256 debt_,
        uint256 backingPerDebtUsd_,
        uint8 debtDecimals_,
        uint256 minCollateralRatioBps_,
        uint256 backingMultiplierBps_
    ) public pure returns (uint256) {
        uint256 marketRequirementUsd = FullMath.mulDivUp(
            debtValueUsd_,
            minCollateralRatioBps_,
            BPS
        );
        uint256 backingRequirementUsd = requiredBackingUsd(
            debt_,
            backingPerDebtUsd_,
            debtDecimals_,
            backingMultiplierBps_
        );
        return
            marketRequirementUsd > backingRequirementUsd
                ? marketRequirementUsd
                : backingRequirementUsd;
    }

    function requiredCollateralAsset(
        uint256 requiredCollateralUsd_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) public pure returns (uint256) {
        return
            FullMath.mulDivUp(
                requiredCollateralUsd_,
                scale(collateralDecimals_),
                collateralUsdPrice_
            );
    }

    function healthFactor(
        uint256 riskAdjustedCollateralUsd_,
        uint256 requiredCollateralUsd_
    ) public pure returns (uint256) {
        if (requiredCollateralUsd_ == 0) return type(uint256).max;
        return FullMath.mulDiv(riskAdjustedCollateralUsd_, WAD, requiredCollateralUsd_);
    }

    function assetUtilizationWad(uint256 debt_, uint256 cap_) public pure returns (uint256) {
        if (cap_ == 0) return debt_ == 0 ? 0 : type(uint256).max;
        return FullMath.mulDivUp(debt_, WAD, cap_);
    }

    function feeRateWad(
        uint256 utilizationWad_,
        uint16 baseFeeBps_,
        uint16 kinkBps_,
        uint16 preKinkSlopeBps_,
        uint16 postKinkSlopeBps_
    ) public pure returns (uint256) {
        uint256 baseFeeRateWad = uint256(baseFeeBps_) * (WAD / BPS);
        if (kinkBps_ == 0) {
            return baseFeeRateWad + FullMath.mulDiv(utilizationWad_, preKinkSlopeBps_, BPS);
        }

        uint256 kinkWad = uint256(kinkBps_) * (WAD / BPS);
        if (utilizationWad_ <= kinkWad) {
            return
                baseFeeRateWad +
                FullMath.mulDiv(utilizationWad_, uint256(preKinkSlopeBps_) * WAD, kinkWad * BPS);
        }

        return
            baseFeeRateWad +
            uint256(preKinkSlopeBps_) *
            (WAD / BPS) +
            FullMath.mulDiv(
                utilizationWad_ - kinkWad,
                uint256(postKinkSlopeBps_) * WAD,
                (WAD - kinkWad) * BPS
            );
    }

    function borrowFee(
        uint256 incrementalRequiredCollateral_,
        uint256 feeRateWad_
    ) public pure returns (uint256) {
        return FullMath.mulDivUp(incrementalRequiredCollateral_, feeRateWad_, WAD);
    }
}
