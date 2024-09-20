// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";
import {FullMath} from "libraries/FullMath.sol";

import {IBondSDA} from "interfaces/IBondSDA.sol";

import {RolesConsumer, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {PRICEv1} from "modules/PRICE/PRICE.v1.sol";
import {RANGEv2} from "modules/RANGE/RANGE.v2.sol";

interface BACKINGv1 {
    function update(uint256 supplyAdded, uint256 reservesAdded) external;
    function price() external view returns (uint256);
}

contract EmissionManager {
    event Sale(uint256 marketID, uint256 saleAmount);

    struct Sale {
        uint256 premium;
        uint256 emissionRate;
        uint256 supplyAdded;
        uint256 reservesAdded;
    }
    Sale[] public sales;

    // Modules
    TRSRYv1 public TRSRY;
    PRICEv1 public PRICE;
    RANGEv2 public RANGE;
    BACKINGv1 public BACKING;

    // Tokens
    ERC20 public immutable ohm;
    ERC20 public immutable dai;

    uint256 public counter;

    uint256 public baseEmissionRate;
    uint256 public minimumPremium;

    constructor() {}

    /// @notice calculate and execute sale, if applicable, once per day
    /// @notice only callable by Olympus Heart
    function execute() external onlyHeart {
        counter++;
        if (counter != 2) return;
        counter = 0;

        // First see if it needs to do book keeping for previous day
        Sale storage previousSale = sales[sales.length - 1];
        uint256 currentBalanceDAI = dai.balanceOf(address(this));
        uint256 currentBalanceOHM = ohm.balanceOf(address(this));

        // Book keeping is needed if there are unspent tokens to accounted for
        if (currentBalanceOHM > 0) previousSale.supplyAdded -= currentBalanceOHM;

        // And/or new reserves, for which it:
        if (currentBalanceDAI > 0) {
            // Logs the inflow and sweeps them to the treasury as sDAI
            previousSale.reservesAdded += currentBalanceDAI;
            sdai.deposit(currentBalanceDAI, address(TRSRY), address(this));

            // And updates backing price in the BACKING module
            BACKING.update(previousSale.supplyAdded, previousSale.reservesAdded);
        }

        // It then calculates the amount to sell for the coming day
        uint256 sell = _calculateSale();

        // If that amount is not zero, it mints the tokens needed and creates a market
        if (sell != 0) {
            MINTR.mint(address(this), sell - currentBalanceOHM);
            _createMarket(sell);

            // If there is no sale for the day, it burns any unsold ohm held
        } else if (currentBalanceOHM != 0) ohm.burn(currentBalanceOHM);
    }

    /// @notice calculate sale amount as a function of premium, minimum premium, and base emission rate
    /// @return emission amount, in OHM
    function _calculateSale() internal view returns (uint256) {
        // To calculate the sale, it first computes premium (market price / backing price)
        uint256 price = PRICE.getLastPrice();
        uint256 backingPrice = BACKING.price();
        uint256 premium = (price * DECIMALS) / backingPrice;

        uint256 emissionRate;
        uint256 supplyToAdd;

        // If the premium is greater than the minimum premium, it computes the emission rate and nominal emissions
        if (premium >= minimumPremium) {
            emissionRate = (baseEmissionRate * premium) / minimumPremium;
            supplyToAdd = (ohm.circulatingSupply() * emissionRate) / DECIMALS;
        }

        // It then logs this information for future use
        sales.push(Sale(premium, emissionRate, supplyToAdd, 0));

        // Before returning the number of tokens to sell
        return supplyToAdd;
    }

    /// @notice create bond protocol market with given budget
    /// @param saleAmount amount of DAI to fund bond market with
    function _createMarket(uint256 saleAmount) internal {
        // Calculate inverse prices from the oracle feed
        // The start price is the current market price, which is also the last price since this is called on a heartbeat
        // The min price is the upper cushion price, since we don't want to buy above this level
        uint256 minPrice = 10 ** (_oracleDecimals * 2) / RANGE.price(false, false); // lower cushion = (false, false) => high = true, wall = false
        uint256 initialPrice = 10 ** (_oracleDecimals * 2) / PRICE.getLastPrice();

        // Calculate scaleAdjustment for bond market
        // Price decimals are returned from the perspective of the quote token
        // so the operations assume payoutPriceDecimal is zero and quotePriceDecimals
        // is the priceDecimal value
        int8 priceDecimals = _getPriceDecimals(initialPrice);
        int8 scaleAdjustment = int8(_daiDecimals) - int8(_ohmDecimals) + (priceDecimals / 2);

        // Calculate oracle scale and bond scale with scale adjustment and format prices for bond market
        uint256 oracleScale = 10 ** uint8(int8(_oracleDecimals) - priceDecimals);
        uint256 bondScale = 10 **
            uint8(36 + scaleAdjustment + int8(_ohmDecimals) - int8(_daiDecimals) - priceDecimals);

        // Approve DAI on the bond teller
        ohm.safeApprove(address(teller), saleAmount);

        // Create new bond market to buy OHM with the reserve
        uint256 marketId = auctioneer.createMarket(
            abi.encode(
                IBondSDA.MarketParams({
                    payoutToken: ohm,
                    quoteToken: dai,
                    callbackAddr: address(0),
                    capacityInQuote: false,
                    capacity: saleAmount,
                    formattedInitialPrice: initialPrice.mulDiv(bondScale, oracleScale),
                    formattedMinimumPrice: minPrice.mulDiv(bondScale, oracleScale),
                    debtBuffer: 100_000, // 100%
                    vesting: uint48(0), // Instant swaps
                    conclusion: uint48(block.timestamp + 1 days), // 1 day from now
                    depositInterval: uint32(4 hours), // 4 hours
                    scaleAdjustment: scaleAdjustment
                })
            )
        );

        emit Sale(marketId, saleAmount);
    }

    /// @notice set the base emissions rate
    /// @param newBaseRate_ uint256
    function setBaseRate(uint256 newBaseRate_) external permissioned {
        baseEmissionRate = newBaseRate_;
    }

    /// @notice set the minimum premium for emissions
    /// @param newMinimumPremium_ uint256
    function setMinimumPremium(uint256 newMinimumPremium_) external permissioned {
        minimumPremium = newMinimumPremium_;
    }
}
