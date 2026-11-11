// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";

/// @title Burner Loans Calculator
/// @notice Compile-time scale-aware arithmetic used by Risk. No deployed or linked runtime.
library LoanMath {
    /// @dev 10**77 is the largest base-ten integer scale representable by uint256.
    uint8 internal constant _MAX_SCALE_DECIMALS = 77;

    /// @dev Basis-point denominator.
    uint256 internal constant _BPS = 10_000;

    /// @dev Fixed-point scale for ratios and health factors.
    uint256 internal constant _WAD = 1e18;

    /// @dev Exact number of WAD units represented by one basis point.
    uint256 internal constant _BPS_TO_WAD = _WAD / _BPS;

    /// @notice A base-ten scale cannot be represented by uint256.
    /// @param decimals Invalid decimal precision.
    error LoanMath_UnsupportedDecimals(uint8 decimals);

    /// @notice Returns the integer scale for a decimal precision.
    /// @param decimals_ Number of decimal places.
    /// @return uint256 Decimal scale equal to `10 ** decimals_`.
    function scale(uint8 decimals_) internal pure returns (uint256) {
        if (decimals_ > _MAX_SCALE_DECIMALS) revert LoanMath_UnsupportedDecimals(decimals_);
        return 10 ** uint256(decimals_);
    }

    /// @notice Converts debt units into quote currency value, rounding up in favor of the protocol.
    /// @param debt_ Debt amount in debt-token decimals.
    /// @param debtPrice_ Quote currency price in oracle decimals.
    /// @param debtDecimals_ Decimal precision of the debt token.
    /// @return uint256 Debt value in the price's decimal scale.
    function debtValue(
        uint256 debt_,
        uint256 debtPrice_,
        uint8 debtDecimals_
    ) internal pure returns (uint256) {
        // Debt units * quote-per-token / token scale = oracle-scaled value. Rounding debt upward
        // and collateral downward prevents precision loss from making a position appear healthier.
        // Math handles phantom overflow and supplies the standard arithmetic panics on invalid results.
        return Math.mulDiv(debt_, debtPrice_, scale(debtDecimals_), Math.Rounding.Ceil);
    }

    /// @notice Converts collateral units into quote currency value, rounding down in favor of the protocol.
    /// @param collateral_ Collateral amount in collateral-token decimals.
    /// @param collateralPrice_ Quote currency price in oracle decimals.
    /// @param collateralDecimals_ Decimal precision of the collateral token.
    /// @return uint256 Collateral value in the price's decimal scale.
    function collateralValue(
        uint256 collateral_,
        uint256 collateralPrice_,
        uint8 collateralDecimals_
    ) internal pure returns (uint256) {
        return Math.mulDiv(collateral_, collateralPrice_, scale(collateralDecimals_));
    }

    /// @notice Calculates the backing-based collateral requirement for debt.
    /// @param debt_ Debt amount in debt-token decimals.
    /// @param backingPerDebt_ Backing value per whole debt token in quote currency.
    /// @param debtDecimals_ Decimal precision of the debt token.
    /// @param backingMultiplierBps_ Backing multiplier in basis points.
    /// @return uint256 Backing requirement in quote currency, rounded up.
    function requiredBackingValue(
        uint256 debt_,
        uint256 backingPerDebt_,
        uint8 debtDecimals_,
        uint256 backingMultiplierBps_
    ) internal pure returns (uint256) {
        return
            Math.mulDiv(
                debtValue(debt_, backingPerDebt_, debtDecimals_),
                backingMultiplierBps_,
                _BPS,
                Math.Rounding.Ceil
            );
    }

    /// @notice Returns the larger of market-LTV and backing collateral requirements.
    /// @dev `debtValue_` is oracle-scaled quote value, while `_BPS` and `maxLtvBps_` use the
    ///      basis-point scale. Therefore, `debtValue_ * _BPS / maxLtvBps_` remains
    ///      oracle-scaled quote value. Math.Rounding.Ceil rounds this maximum-LTV requirement upward.
    /// @param debtValue_ Market value of the debt in quote currency.
    /// @param debt_ Debt amount in debt-token decimals.
    /// @param backingPerDebt_ Backing value per whole debt token in quote currency.
    /// @param debtDecimals_ Decimal precision of the debt token.
    /// @param maxLtvBps_ Maximum loan-to-value ratio in basis points.
    /// @param backingMultiplierBps_ Backing multiplier in basis points.
    /// @return uint256 Required collateral value in quote currency, rounded up.
    function requiredCollateralValue(
        uint256 debtValue_,
        uint256 debt_,
        uint256 backingPerDebt_,
        uint8 debtDecimals_,
        uint256 maxLtvBps_,
        uint256 backingMultiplierBps_
    ) internal pure returns (uint256) {
        // Apply both constraints to the same quote-currency scale; satisfying only one is insufficient.
        uint256 marketRequirement = Math.mulDiv(debtValue_, _BPS, maxLtvBps_, Math.Rounding.Ceil);
        uint256 backingRequirement = requiredBackingValue(
            debt_,
            backingPerDebt_,
            debtDecimals_,
            backingMultiplierBps_
        );
        return marketRequirement > backingRequirement ? marketRequirement : backingRequirement;
    }

    /// @notice Converts a quote currency collateral requirement into collateral-token units.
    /// @param requiredCollateralValue_ Required collateral value in quote currency.
    /// @param collateralPrice_ Quote currency price per whole collateral token.
    /// @param collateralDecimals_ Decimal precision of the collateral token.
    /// @return uint256 Required collateral amount, rounded up.
    function requiredCollateralAsset(
        uint256 requiredCollateralValue_,
        uint256 collateralPrice_,
        uint8 collateralDecimals_
    ) internal pure returns (uint256) {
        return
            Math.mulDiv(
                requiredCollateralValue_,
                scale(collateralDecimals_),
                collateralPrice_,
                Math.Rounding.Ceil
            );
    }

    /// @notice Calculates the WAD-scaled collateral health factor.
    /// @dev Returns `type(uint256).max` when no collateral requirement exists.
    /// @dev Both quote currency inputs use the same current oracle decimal precision, which need not be 18.
    ///      Their quote currency scale cancels in the ratio; multiplying by `_WAD`
    ///      and dividing by an oracle-scaled quote requirement produces a WAD-scaled result.
    /// @param collateralValue_ Gross collateral quote currency value in oracle decimals.
    /// @param requiredCollateralValue_ Required collateral quote currency value in the same oracle decimals.
    /// @return uint256 Health factor scaled by 1e18 and rounded down.
    function healthFactor(
        uint256 collateralValue_,
        uint256 requiredCollateralValue_
    ) internal pure returns (uint256) {
        if (requiredCollateralValue_ == 0) return type(uint256).max;
        return Math.mulDiv(collateralValue_, _WAD, requiredCollateralValue_);
    }

    /// @notice Calculates asset debt utilization, rounded up.
    /// @dev Returns max uint when debt is nonzero and the cap is zero.
    /// @param debt_ Active asset debt.
    /// @param cap_ Asset debt cap.
    /// @return uint256 Utilization scaled by 1e18.
    function assetUtilizationWad(uint256 debt_, uint256 cap_) internal pure returns (uint256) {
        if (cap_ == 0) return debt_ == 0 ? 0 : type(uint256).max;
        return Math.mulDiv(debt_, _WAD, cap_, Math.Rounding.Ceil);
    }

    /// @notice Calculates the WAD-scaled fee rate for a kinked utilization curve.
    /// @dev A zero kink applies the pre-kink slope across the full utilization range.
    /// @param utilizationWad_ Utilization scaled by 1e18.
    /// @param baseFeeBps_ Base fee in basis points.
    /// @param kinkBps_ Utilization kink in basis points.
    /// @param preKinkSlopeBps_ Fee slope below the kink in basis points.
    /// @param postKinkSlopeBps_ Fee slope above the kink in basis points.
    /// @return uint256 Fee rate scaled by 1e18.
    function feeRateWad(
        uint256 utilizationWad_,
        uint16 baseFeeBps_,
        uint16 kinkBps_,
        uint16 preKinkSlopeBps_,
        uint16 postKinkSlopeBps_
    ) internal pure returns (uint256) {
        uint256 baseFeeRateWad = uint256(baseFeeBps_) * _BPS_TO_WAD;
        if (kinkBps_ == 0) {
            return baseFeeRateWad + Math.mulDiv(utilizationWad_, preKinkSlopeBps_, _BPS);
        }

        uint256 kinkWad = uint256(kinkBps_) * _BPS_TO_WAD;
        // Each slope is the total fee increase across its segment. Dividing by the segment width
        // reaches the full pre-kink increase exactly at the kink and keeps the two segments continuous.
        if (utilizationWad_ <= kinkWad) {
            return
                baseFeeRateWad +
                Math.mulDiv(utilizationWad_, uint256(preKinkSlopeBps_) * _WAD, kinkWad * _BPS);
        }

        return
            baseFeeRateWad +
            uint256(preKinkSlopeBps_) *
            _BPS_TO_WAD +
            Math.mulDiv(
                utilizationWad_ - kinkWad,
                uint256(postKinkSlopeBps_) * _WAD,
                (_WAD - kinkWad) * _BPS
            );
    }

    /// @notice Calculates the borrow fee on incremental required collateral.
    /// @param incrementalRequiredCollateral_ Incremental collateral requirement in asset units.
    /// @param feeRateWad_ Fee rate scaled by 1e18.
    /// @return uint256 Borrow fee in collateral units, rounded up.
    function borrowFee(
        uint256 incrementalRequiredCollateral_,
        uint256 feeRateWad_
    ) internal pure returns (uint256) {
        return Math.mulDiv(incrementalRequiredCollateral_, feeRateWad_, _WAD, Math.Rounding.Ceil);
    }
}
