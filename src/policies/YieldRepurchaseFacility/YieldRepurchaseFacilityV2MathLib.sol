// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// The library gathers the arithmetic of the facility in one place so that the lens and the
// tests compute through the same formulas; several of them have a single production caller.
// forge-lint: disable-start(internal-function-used-once)

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";

/// @title YieldRepurchaseFacilityV2MathLib
/// @notice An internal library of the arithmetic of the YieldRepurchaseFacilityV2: the
///         yield projection, the Clearinghouse interest, the backing of the purchased
///         OHM, and the bond market pricing.
/// @dev The functions are pure and take values, so the facility, its linked libraries,
///      and the lens compute through the same formulas. Every division floors unless
///      stated otherwise.
library YieldRepurchaseFacilityV2MathLib {
    using FullMath for uint256;

    /// @notice Numerator of the Clearinghouse annual interest rate (0.5%).
    uint256 internal constant CH_RATE_NUMERATOR = 5;

    /// @notice Denominator of the Clearinghouse annual interest rate (`5 / 1000` = 0.5%).
    uint256 internal constant CH_RATE_DENOMINATOR = 1000;

    /// @notice Number of weeks per year used for the Clearinghouse annual rate.
    uint256 internal constant WEEKS_PER_YEAR = 52;

    /// @notice The base exponent of the Bond SDA market scale: a market's `scale` is
    ///         `10 ** (BOND_SCALE_DECIMALS + scaleAdjustment)`.
    int8 internal constant BOND_SCALE_DECIMALS = 36;

    /// @notice The inputs of the bond market pricing.
    /// @param oraclePrice The price of one quote token (OHM) unit, denominated in the
    ///        payout token, in oracle decimals.
    /// @param initialDiscount The discount applied to the oracle price for the initial
    ///        market price (`1e18` = 100%).
    /// @param maxPricePremium The premium over the oracle price at which the market
    ///        floor is set (`1e18` = 100%), capping the payout per quote token. A zero
    ///        premium caps the payout at the oracle price.
    /// @param oracleDecimals The decimals of `oraclePrice`.
    /// @param quoteDecimals The quote token (OHM) decimals.
    /// @param payoutDecimals The payout token decimals.
    struct MarketPricing {
        uint256 oraclePrice;
        uint256 initialDiscount;
        uint256 maxPricePremium;
        uint8 oracleDecimals;
        uint8 quoteDecimals;
        uint8 payoutDecimals;
    }

    // ============ YIELD ============ //

    /// @notice Returns the vault yield accrued since the snapshots, in reserve units.
    /// @dev `lastReserveBalance * (currentRate - lastRate) / lastRate`, floored. Zero
    ///      when the rate has not increased or the rate snapshot is unset.
    /// @param lastReserveBalance_ The reserve balance snapshot, in reserve units.
    /// @param lastRate_ The conversion rate snapshot: the reserve value of one whole
    ///        share.
    /// @param currentRate_ The current conversion rate.
    /// @return yield The accrued yield, in reserve units.
    function vaultYield(
        uint256 lastReserveBalance_,
        uint256 lastRate_,
        uint256 currentRate_
    ) internal pure returns (uint256 yield) {
        if (lastRate_ == 0) return 0;
        if (currentRate_ <= lastRate_) return 0;

        yield = lastReserveBalance_.mulDiv(currentRate_ - lastRate_, lastRate_);
    }

    /// @notice Projects the next yield of a vault, in reserve units: the total yield
    ///         multiplied by the vault's buyback share (floor).
    /// @param vaultYield_ The vault yield accrued since the snapshots, in reserve units.
    /// @param clearinghouseYield_ The weekly Clearinghouse interest credited to the
    ///        vault, in reserve units; zero for a vault other than the backing vault.
    /// @param yieldBuybackShare_ The share of the yield routed to buybacks (`1e18` =
    ///        100%).
    /// @return The projected yield, in reserve units.
    function projectNextYield(
        uint256 vaultYield_,
        uint256 clearinghouseYield_,
        uint256 yieldBuybackShare_
    ) internal pure returns (uint256) {
        uint256 totalYield = vaultYield_ + clearinghouseYield_;
        return
            totalYield.mulDiv(
                yieldBuybackShare_,
                YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT
            );
    }

    /// @notice Returns one week of interest on the effective receivables of a
    ///         Clearinghouse.
    /// @dev The offset is subtracted with saturation; the rate is 0.5% per year divided
    ///      over 52 weeks, floored at each division.
    /// @param receivables_ The Clearinghouse's `principalReceivables`.
    /// @param offset_ The cumulative receivables offset.
    /// @return The weekly interest, in the receivables' units.
    function clearinghouseInterest(
        uint256 receivables_,
        uint256 offset_
    ) internal pure returns (uint256) {
        uint256 effective = Math.saturatingSub(receivables_, offset_);
        return (effective * CH_RATE_NUMERATOR) / CH_RATE_DENOMINATOR / WEEKS_PER_YEAR;
    }

    /// @notice Returns the part of a funding target the treasury withdrawal did not
    ///         cover: `target - funded`, floored at zero.
    /// @param target_ The funding target, in reserve units.
    /// @param funded_ The funded value, in reserve units.
    /// @return The unfunded remainder, in reserve units.
    function unfundedRemainder(uint256 target_, uint256 funded_) internal pure returns (uint256) {
        return Math.saturatingSub(target_, funded_);
    }

    // ============ BACKING ============ //

    /// @notice Returns the backing of an OHM amount, in the backing decimals.
    /// @dev `purchased (ohmDecimals) * backingPerOhm (18 decimals) / 10 ** ohmDecimals`
    ///      -> 18 decimals (floor).
    /// @param purchased_ The OHM amount, in OHM decimals.
    /// @param backingPerOhm_ The backing of one OHM, in 18 decimals.
    /// @param ohmDecimals_ The OHM decimals.
    /// @return The backing amount, in 18 decimals.
    function backingAmount(
        uint256 purchased_,
        uint256 backingPerOhm_,
        uint8 ohmDecimals_
    ) internal pure returns (uint256) {
        return
            purchased_.mulDiv(
                backingPerOhm_,
                YieldRepurchaseFacilityV2Constants.DECIMAL_BASE ** ohmDecimals_
            );
    }

    /// @notice Scales a backing amount, in the backing decimals, down to the target
    ///         decimals, flooring.
    /// @param backingAmount_ The backing amount, in 18 decimals.
    /// @param targetDecimals_ The target decimals, at most 18.
    /// @return The scaled amount, in the target decimals.
    function scaleBackingAmount(
        uint256 backingAmount_,
        uint8 targetDecimals_
    ) internal pure returns (uint256) {
        if (targetDecimals_ == YieldRepurchaseFacilityV2Constants.BACKING_DECIMALS)
            return backingAmount_;
        return
            backingAmount_ /
            (YieldRepurchaseFacilityV2Constants.DECIMAL_BASE **
                (YieldRepurchaseFacilityV2Constants.BACKING_DECIMALS - targetDecimals_));
    }

    /// @notice Returns the OHM to burn against a funded backing withdrawal.
    /// @dev The whole purchased amount when the funded value covers the backing amount,
    ///      otherwise the purchased amount pro-rated by `funded / backingAmount`
    ///      (floor). The explicit full branch avoids the pro-rating rounding when the
    ///      treasury covers the backing in full.
    /// @param purchased_ The purchased OHM, in OHM decimals.
    /// @param funded_ The value of the withdrawn backing shares, in reserve units.
    /// @param backingAmount_ The backing of the purchased OHM, in reserve units; must be
    ///        non-zero.
    /// @return The OHM to burn, in OHM decimals.
    function ohmToBurn(
        uint256 purchased_,
        uint256 funded_,
        uint256 backingAmount_
    ) internal pure returns (uint256) {
        return funded_ >= backingAmount_ ? purchased_ : purchased_.mulDiv(funded_, backingAmount_);
    }

    // ============ MARKET PRICING ============ //

    /// @notice Computes the Bond SDA price parameters for a market quoted in OHM.
    /// @dev The market quotes OHM per payout unit, so the prices are inverses of the
    ///      oracle price: the initial price applies the discount to the oracle price,
    ///      and the minimum price corresponds to the oracle price raised by the max
    ///      price premium, capping the payout per OHM at
    ///      `oraclePrice * (1 + maxPricePremium)`.
    ///
    ///      Both parameters are measured from the same oracle price, so they are
    ///      independent: the discount sets where a market opens, and the premium sets
    ///      the ceiling of what the facility pays for one OHM. A zero premium caps the
    ///      payout at the oracle price itself.
    ///
    ///      The SDA decays the market price toward the minimum price, so the width of
    ///      the decay band is `(1 + maxPricePremium) / (1 - initialDiscount)`: the room
    ///      a market has to reach a clearing price. Only a zero premium combined with a
    ///      zero discount pins the market at the oracle price.
    ///
    ///      The premium is non-negative and the discount is below 100%, so
    ///      `maxPrice >= effectivePrice` and therefore
    ///      `formattedMinimumPrice <= formattedInitialPrice` for every configuration.
    ///      The Bond SDA rejects a market whose initial price is below its minimum
    ///      price, so this ordering must hold.
    ///
    ///      The inversions floor, and the scale factors follow the Bond SDA
    ///      `scaleAdjustment` convention. A checked cast on an extreme price reverts.
    /// @param pricing_ The pricing inputs.
    /// @return formattedInitialPrice The Bond SDA initial price.
    /// @return formattedMinimumPrice The Bond SDA minimum price.
    /// @return scaleAdjustment The Bond SDA scale adjustment.
    function marketPricing(
        MarketPricing memory pricing_
    )
        internal
        pure
        returns (uint256 formattedInitialPrice, uint256 formattedMinimumPrice, int8 scaleAdjustment)
    {
        // discountFactor = 1e18 - initialDiscount (both 18 decimals);
        // e.g. 1e18 - 3e16 = 0.97e18.
        uint256 discountFactor = YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT -
            pricing_.initialDiscount;
        // effectivePrice = oraclePrice (oracleDecimals) * discountFactor (18 decimals)
        // / 1e18 -> oracleDecimals (floor).
        uint256 effectivePrice = pricing_.oraclePrice.mulDiv(
            discountFactor,
            YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT
        );
        // premiumFactor = 1e18 + maxPricePremium (18 decimals); e.g. 1e18 + 1e17 = 1.1e18.
        // maxPrice = oraclePrice (oracleDecimals) * premiumFactor (18 decimals)
        // / 1e18 -> oracleDecimals (floor). This is the highest payout the market can
        // reach for one quote token; a zero premium leaves it at the oracle price.
        uint256 maxPrice = pricing_.oraclePrice.mulDiv(
            YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT + pricing_.maxPricePremium,
            YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT
        );
        uint256 oracleSquare = YieldRepurchaseFacilityV2Constants.DECIMAL_BASE **
            (uint256(pricing_.oracleDecimals) * 2);

        uint256 initialPrice = oracleSquare / effectivePrice;
        uint256 minPrice = oracleSquare / maxPrice;

        int8 priceDecimals = _priceDecimals(initialPrice, pricing_.oracleDecimals);
        // The payout decimals are validated at most 18, OHM has 9 decimals, and the facility
        // pins the oracle decimals at 18, so no int8 cast truncates; `priceDecimals` lies in
        // [-18, 18] because `initialPrice` is at most 10 ** 36, so neither uint8 exponent is
        // negative.
        // forge-lint: disable-start(unsafe-typecast)
        scaleAdjustment =
            int8(pricing_.payoutDecimals) -
            int8(pricing_.quoteDecimals) +
            (priceDecimals / 2);

        uint256 oracleScale = YieldRepurchaseFacilityV2Constants.DECIMAL_BASE **
            uint8(int8(pricing_.oracleDecimals) - priceDecimals);
        uint256 bondScale = YieldRepurchaseFacilityV2Constants.DECIMAL_BASE **
            uint8(
                BOND_SCALE_DECIMALS +
                    scaleAdjustment +
                    int8(pricing_.quoteDecimals) -
                    int8(pricing_.payoutDecimals) -
                    priceDecimals
            );
        // forge-lint: disable-end(unsafe-typecast)

        formattedInitialPrice = initialPrice.mulDiv(bondScale, oracleScale);
        formattedMinimumPrice = minPrice.mulDiv(bondScale, oracleScale);
    }

    /// @notice Returns the order of magnitude of `price_` relative to the oracle
    ///         decimals.
    function _priceDecimals(
        uint256 price_,
        uint8 oracleDecimals_
    ) private pure returns (int8 relativeDecimals) {
        int8 decimals;
        while (price_ >= YieldRepurchaseFacilityV2Constants.DECIMAL_BASE) {
            price_ = price_ / YieldRepurchaseFacilityV2Constants.DECIMAL_BASE;
            ++decimals;
        }
        // The facility pins the oracle decimals at 18, which fits in int8
        // forge-lint: disable-next-line(unsafe-typecast)
        return decimals - int8(oracleDecimals_);
    }
}
// forge-lint: disable-end(internal-function-used-once)
