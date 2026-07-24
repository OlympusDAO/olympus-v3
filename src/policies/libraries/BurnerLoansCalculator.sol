// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

/// @title Burner Loans Calculator
/// @notice Separately linked scale-aware calculations used by Burner Loans lifecycle policies.
library BurnerLoansCalculator {
    /// @dev Basis-point denominator.
    uint256 internal constant BPS = 10_000;

    /// @dev Fixed-point scale for ratios and health factors.
    uint256 internal constant WAD = 1e18;

    /// @notice Returns the integer scale for a decimal precision.
    /// @param decimals_ Number of decimal places.
    /// @return Decimal scale equal to `10 ** decimals_`.
    function scale(uint8 decimals_) public pure returns (uint256) {
        return 10 ** uint256(decimals_);
    }

    /// @notice Converts debt units into USD value, rounding up in favor of the protocol.
    /// @param debt_ Debt amount in debt-token decimals.
    /// @param debtUsdPrice_ USD price in price-oracle decimals.
    /// @param debtDecimals_ Decimal precision of the debt token.
    /// @return Debt value in the price's decimal scale.
    function debtValueUsd(
        uint256 debt_,
        uint256 debtUsdPrice_,
        uint8 debtDecimals_
    ) public pure returns (uint256) {
        return FullMath.mulDivUp(debt_, debtUsdPrice_, scale(debtDecimals_));
    }

    /// @notice Converts collateral units into USD value, rounding down in favor of the protocol.
    /// @param collateral_ Collateral amount in collateral-token decimals.
    /// @param collateralUsdPrice_ USD price in price-oracle decimals.
    /// @param collateralDecimals_ Decimal precision of the collateral token.
    /// @return Collateral value in the price's decimal scale.
    function collateralValueUsd(
        uint256 collateral_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) public pure returns (uint256) {
        return FullMath.mulDiv(collateral_, collateralUsdPrice_, scale(collateralDecimals_));
    }

    /// @notice Applies the configured collateral factor to a collateral USD value.
    /// @param collateralValueUsd_ Gross collateral value in USD.
    /// @param collateralFactorBps_ Collateral factor in basis points.
    /// @return Risk-adjusted collateral value in USD, rounded down.
    function riskAdjustedCollateralUsd(
        uint256 collateralValueUsd_,
        uint256 collateralFactorBps_
    ) public pure returns (uint256) {
        return FullMath.mulDiv(collateralValueUsd_, collateralFactorBps_, BPS);
    }

    /// @notice Calculates the backing-based collateral requirement for debt.
    /// @param debt_ Debt amount in debt-token decimals.
    /// @param backingPerDebtUsd_ Backing value per whole debt token in USD.
    /// @param debtDecimals_ Decimal precision of the debt token.
    /// @param backingMultiplierBps_ Backing multiplier in basis points.
    /// @return Backing requirement in USD, rounded up.
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

    /// @notice Returns the larger of market-ratio and backing collateral requirements.
    /// @param debtValueUsd_ Market value of the debt in USD.
    /// @param debt_ Debt amount in debt-token decimals.
    /// @param backingPerDebtUsd_ Backing value per whole debt token in USD.
    /// @param debtDecimals_ Decimal precision of the debt token.
    /// @param minCollateralRatioBps_ Minimum collateral ratio in basis points.
    /// @param backingMultiplierBps_ Backing multiplier in basis points.
    /// @return Required collateral value in USD, rounded up.
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

    /// @notice Converts a USD collateral requirement into collateral-token units.
    /// @param requiredCollateralUsd_ Required collateral value in USD.
    /// @param collateralUsdPrice_ USD price per whole collateral token.
    /// @param collateralDecimals_ Decimal precision of the collateral token.
    /// @return Required collateral amount, rounded up.
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

    /// @notice Calculates the WAD-scaled collateral health factor.
    /// @dev Returns `type(uint256).max` when no collateral requirement exists.
    /// @param riskAdjustedCollateralUsd_ Risk-adjusted collateral value in USD.
    /// @param requiredCollateralUsd_ Required collateral value in USD.
    /// @return Health factor scaled by 1e18 and rounded down.
    function healthFactor(
        uint256 riskAdjustedCollateralUsd_,
        uint256 requiredCollateralUsd_
    ) public pure returns (uint256) {
        if (requiredCollateralUsd_ == 0) return type(uint256).max;
        return FullMath.mulDiv(riskAdjustedCollateralUsd_, WAD, requiredCollateralUsd_);
    }

    /// @notice Calculates asset debt utilization, rounded up.
    /// @dev Returns max uint when debt is nonzero and the cap is zero.
    /// @param debt_ Active asset debt.
    /// @param cap_ Asset debt cap.
    /// @return Utilization scaled by 1e18.
    function assetUtilizationWad(uint256 debt_, uint256 cap_) public pure returns (uint256) {
        if (cap_ == 0) return debt_ == 0 ? 0 : type(uint256).max;
        return FullMath.mulDivUp(debt_, WAD, cap_);
    }

    /// @notice Calculates the WAD-scaled fee rate for a kinked utilization curve.
    /// @dev A zero kink applies the pre-kink slope across the full utilization range.
    /// @param utilizationWad_ Utilization scaled by 1e18.
    /// @param baseFeeBps_ Base fee in basis points.
    /// @param kinkBps_ Utilization kink in basis points.
    /// @param preKinkSlopeBps_ Fee slope below the kink in basis points.
    /// @param postKinkSlopeBps_ Fee slope above the kink in basis points.
    /// @return Fee rate scaled by 1e18.
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

    /// @notice Calculates the borrow fee on incremental required collateral.
    /// @param incrementalRequiredCollateral_ Incremental collateral requirement in asset units.
    /// @param feeRateWad_ Fee rate scaled by 1e18.
    /// @return Borrow fee in collateral units, rounded up.
    function borrowFee(
        uint256 incrementalRequiredCollateral_,
        uint256 feeRateWad_
    ) public pure returns (uint256) {
        return FullMath.mulDivUp(incrementalRequiredCollateral_, feeRateWad_, WAD);
    }
}
