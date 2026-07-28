// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBondSDA} from "src/interfaces/IBondSDA.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Contracts
import {ERC20 as SolmateERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

/// @title YRFBondMarketLib
/// @notice An external library that prices and submits the Bond Protocol SDA markets of
///         the YieldRepurchaseFacilityV2.
/// @dev The library is deployed separately and reached through `DELEGATECALL`, so the
///      market submission originates from the calling facility: the facility is the
///      market owner and the market callback, and the auctioneer's callback authorization
///      applies to the facility address.
library YRFBondMarketLib {
    using FullMath for uint256;

    /// @notice Precision denominator of the initial discount (`1e18` = 100%).
    uint256 internal constant ONE_HUNDRED_PERCENT = 1e18;

    /// @notice Bond market debt buffer (`100_000` = 100%).
    uint32 internal constant BOND_DEBT_BUFFER = 100_000;

    /// @notice Bond market deposit interval (4 hours).
    uint32 internal constant BOND_DEPOSIT_INTERVAL = 4 hours;

    /// @notice Bond market duration (24 hours).
    uint48 internal constant BOND_MARKET_DURATION = 1 days;

    /// @notice The inputs of a market submission.
    /// @param auctioneer The SDA auctioneer the market is submitted to.
    /// @param payoutToken The token the market pays out.
    /// @param quoteToken The quote token (OHM).
    /// @param capacity The market capacity, in payout token units.
    /// @param oraclePrice The quote price of one payout unit, in oracle decimals.
    /// @param initialDiscount The discount applied to the oracle price for the initial
    ///        market price (`1e18` = 100%).
    /// @param oracleDecimals The decimals of `oraclePrice`.
    /// @param quoteDecimals The quote token (OHM) decimals.
    /// @param payoutDecimals The payout token decimals.
    struct MarketConfig {
        IBondSDA auctioneer;
        address payoutToken;
        address quoteToken;
        uint256 capacity;
        uint256 oraclePrice;
        uint256 initialDiscount;
        uint8 oracleDecimals;
        uint8 quoteDecimals;
        uint8 payoutDecimals;
    }

    /// @notice Prices and submits a bond market that sells the payout token for OHM.
    /// @dev The market runs for `BOND_MARKET_DURATION` with instant vesting, a
    ///      `BOND_DEPOSIT_INTERVAL` deposit interval, a `BOND_DEBT_BUFFER` debt buffer,
    ///      and the capacity denominated in the payout token; the caller is the market
    ///      callback. A revert of the auctioneer is reported as a failure instead of
    ///      bubbling; a revert of the pricing (a checked cast on an extreme price)
    ///      bubbles to the caller.
    /// @param config_ The market submission inputs.
    /// @return success Whether the auctioneer accepted the market.
    /// @return marketId The market ID assigned by the auctioneer, or zero on a failure.
    function createMarket(
        MarketConfig memory config_
    ) external returns (bool success, uint256 marketId) {
        (
            uint256 formattedInitialPrice,
            uint256 formattedMinimumPrice,
            int8 scaleAdjustment
        ) = _computeMarketPricing(config_);

        try
            config_.auctioneer.createMarket(
                abi.encode(
                    IBondSDA.MarketParams({
                        payoutToken: SolmateERC20(config_.payoutToken),
                        quoteToken: SolmateERC20(config_.quoteToken),
                        callbackAddr: address(this),
                        capacityInQuote: false,
                        capacity: config_.capacity,
                        formattedInitialPrice: formattedInitialPrice,
                        formattedMinimumPrice: formattedMinimumPrice,
                        debtBuffer: BOND_DEBT_BUFFER,
                        vesting: uint48(0),
                        conclusion: uint48(block.timestamp + BOND_MARKET_DURATION),
                        depositInterval: BOND_DEPOSIT_INTERVAL,
                        scaleAdjustment: scaleAdjustment
                    })
                )
            )
        returns (uint256 marketId_) {
            return (true, marketId_);
        } catch {
            return (false, 0);
        }
    }

    /// @notice Computes the Bond SDA price parameters for a market quoted in OHM.
    /// @dev The market quotes OHM per payout unit, so the prices are inverses of the
    ///      oracle price: the initial price applies the discount to the oracle price,
    ///      and the minimum price corresponds to the undiscounted oracle price, capping
    ///      the payout per OHM at the oracle-priced amount. The inversions floor, and
    ///      the scale factors follow the Bond SDA `scaleAdjustment` convention.
    function _computeMarketPricing(
        MarketConfig memory config_
    )
        private
        pure
        returns (uint256 formattedInitialPrice, uint256 formattedMinimumPrice, int8 scaleAdjustment)
    {
        // discount = 1e18 - initialDiscount; e.g. 1e18 - 3e16 = 0.97e18
        uint256 discountFactor = ONE_HUNDRED_PERCENT - config_.initialDiscount;
        uint256 effectivePrice = config_.oraclePrice.mulDiv(discountFactor, ONE_HUNDRED_PERCENT);
        uint256 oracleSquare = 10 ** (uint256(config_.oracleDecimals) * 2);

        uint256 initialPrice = oracleSquare / effectivePrice;
        uint256 minPrice = oracleSquare / config_.oraclePrice;

        int8 priceDecimals = _getPriceDecimals(initialPrice, config_.oracleDecimals);
        scaleAdjustment =
            int8(config_.payoutDecimals) -
            int8(config_.quoteDecimals) +
            (priceDecimals / 2);

        uint256 oracleScale = 10 ** uint8(int8(config_.oracleDecimals) - priceDecimals);
        uint256 bondScale = 10 **
            uint8(
                36 +
                    scaleAdjustment +
                    int8(config_.quoteDecimals) -
                    int8(config_.payoutDecimals) -
                    priceDecimals
            );

        formattedInitialPrice = initialPrice.mulDiv(bondScale, oracleScale);
        formattedMinimumPrice = minPrice.mulDiv(bondScale, oracleScale);
    }

    /// @notice Returns the order of magnitude of `price_` relative to the oracle
    ///         decimals.
    function _getPriceDecimals(
        uint256 price_,
        uint8 oracleDecimals_
    ) private pure returns (int8 relativeDecimals) {
        int8 decimals;
        while (price_ >= 10) {
            price_ = price_ / 10;
            ++decimals;
        }
        return decimals - int8(oracleDecimals_);
    }
}
