// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {FullMath} from "libraries/FullMath.sol";

import {IBondSDA} from "interfaces/IBondSDA.sol";
import {IgOHM} from "interfaces/IgOHM.sol";

import {RolesConsumer, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {PRICEv1} from "modules/PRICE/PRICE.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {CHREGv1} from "modules/CHREG/CHREG.v1.sol";

interface BurnableERC20 {
    function burn(uint256 amount) external;
}

interface Clearinghouse {
    function principalReceivables() external view returns (uint256);
}

contract EmissionManager is Policy, RolesConsumer {
    using FullMath for uint256;

    // ========== ERRORS ========== //

    // ========== EVENTS ========== //

    event SaleCreated(uint256 marketID, uint256 saleAmount);

    // ========== DATA STRUCTURES ========== //

    struct Sale {
        uint256 premium;
        uint256 emissionRate;
        uint256 supplyAdded;
        uint256 reservesAdded;
    }

    struct BaseRateChange {
        uint256 changeBy;
        uint48 beatsLeft;
        bool addition;
    }

    // ========== STATE VARIABLES ========== //
    uint256 public saleCounter;
    Sale[] public sales;

    BaseRateChange public rateChange;

    // Modules
    TRSRYv1 public TRSRY;
    PRICEv1 public PRICE;
    MINTRv1 public MINTR;
    CHREGv1 public CHREG;

    // Tokens
    // solhint-disable const-name-snakecase
    ERC20 public immutable ohm;
    IgOHM public immutable gohm;
    ERC20 public immutable dai;
    ERC4626 public immutable sdai;

    // External contracts
    IBondSDA public auctioneer;
    address public teller;

    // Manager variables
    uint256 public baseEmissionRate;
    uint256 public minimumPremium;
    uint48 public vestingPeriod; // initialized at 0
    uint256 public backing;
    uint8 public beatCounter;
    bool public locallyActive;

    uint8 internal _oracleDecimals;
    uint8 internal immutable _ohmDecimals;
    uint8 internal immutable _reserveDecimals;

    uint48 public shutdownTimestamp;
    uint48 public restartTimeframe;

    // ========== SETUP ========== //

    constructor(
        Kernel kernel_,
        address ohm_,
        address gohm_,
        address dai_,
        address sdai_,
        address auctioneer_,
        address teller_
    ) Policy(kernel_) {
        // Set immutable variables
        if (ohm_ == address(0)) revert("OHM address cannot be 0");
        if (gohm_ == address(0)) revert("gOHM address cannot be 0");
        if (dai_ == address(0)) revert("DAI address cannot be 0");
        if (sdai_ == address(0)) revert("sDAI address cannot be 0");
        if (auctioneer_ == address(0)) revert("Auctioneer address cannot be 0");

        ohm = ERC20(ohm_);
        gohm = IgOHM(gohm_);
        dai = ERC20(dai_);
        sdai = ERC4626(sdai_);
        auctioneer = IBondSDA(auctioneer_);
        teller = teller_;

        _ohmDecimals = ohm.decimals();
        _reserveDecimals = dai.decimals();

        // Max approve sDAI contract for DAI for deposits
        dai.approve(address(sdai), type(uint256).max);
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](5);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("PRICE");
        dependencies[2] = toKeycode("MINTR");
        dependencies[3] = toKeycode("CHREG");
        dependencies[4] = toKeycode("ROLES");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        PRICE = PRICEv1(getModuleAddress(dependencies[1]));
        MINTR = MINTRv1(getModuleAddress(dependencies[2]));
        CHREG = CHREGv1(getModuleAddress(dependencies[3]));
        ROLES = ROLESv1(getModuleAddress(dependencies[4]));

        _oracleDecimals = PRICE.decimals();
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode mintrKeycode = toKeycode("MINTR");

        permissions = new Permissions[](2);
        permissions[0] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
    }

    // ========== HEARTBEAT ========== //

    /// @notice calculate and execute sale, if applicable, once per day
    function execute() external onlyRole("heart") {
        if (!locallyActive) return;

        beatCounter = ++beatCounter % 3;
        if (beatCounter != 0) return;

        if (rateChange.beatsLeft != 0) {
            --rateChange.beatsLeft;
            if (rateChange.addition) baseEmissionRate += rateChange.changeBy;
            else baseEmissionRate -= rateChange.changeBy;
        }

        // Get current balances of the contract
        uint256 currentBalanceDAI = dai.balanceOf(address(this));
        uint256 currentBalanceOHM = ohm.balanceOf(address(this));

        // If there are previous sales, we need to do some book keeping
        uint256 numSales = sales.length;
        if (numSales > 0) {
            Sale storage previousSale = sales[numSales - 1];

            // Book keeping is needed if there are unspent tokens to account for
            if (currentBalanceOHM > 0) previousSale.supplyAdded -= currentBalanceOHM;

            // And/or new reserves, for which it:
            if (currentBalanceDAI > 0) {
                // Logs the inflow and sweeps them to the treasury as sDAI
                previousSale.reservesAdded += currentBalanceDAI;
                sdai.deposit(currentBalanceDAI, address(TRSRY));

                // And updates backing price in the BACKING module
                _updateBacking(previousSale.supplyAdded, previousSale.reservesAdded);
            }
        }

        // It then calculates the amount to sell for the coming day
        uint256 sell = _calculateSale();

        // It brings its ohm holdings into balance with the amount to sell
        if (sell > currentBalanceOHM) {
            uint256 amountToMint = sell - currentBalanceOHM;
            MINTR.increaseMintApproval(address(this), amountToMint);
            MINTR.mintOhm(address(this), amountToMint);
        } else if (currentBalanceOHM > sell)
            BurnableERC20(address(ohm)).burn(currentBalanceOHM - sell);

        // And then opens a market if applicable
        if (sell != 0) _createMarket(sell);
    }

    // ========== INITIALIZE ========== //

    function initialize(
        uint256 baseEmissionsRate_,
        uint256 minimumPremium_,
        uint256 backing_,
        uint48 restartTimeframe_
    ) external onlyRole("emissions_admin") {
        if (locallyActive) revert("Already initialized");

        // Validate
        if (baseEmissionsRate_ == 0) revert("Base emissions rate cannot be 0");
        if (minimumPremium_ == 0) revert("Minimum premium cannot be 0");
        if (backing_ == 0) revert("Backing cannot be 0");
        if (restartTimeframe_ == 0) revert("Restart timeframe cannot be 0");

        // Assign
        baseEmissionRate = baseEmissionsRate_;
        minimumPremium = minimumPremium_;
        backing = backing_;
        restartTimeframe = restartTimeframe_;

        // Activate
        locallyActive = true;
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @notice calculate sale amount as a function of premium, minimum premium, and base emission rate
    /// @return emission amount, in OHM
    function _calculateSale() internal returns (uint256) {
        // To calculate the sale, it first computes premium (market price / backing price)
        uint256 price = PRICE.getLastPrice();
        uint256 premium = (price * 10 ** _reserveDecimals) / backing;

        uint256 emissionRate;
        uint256 supplyToAdd;

        // If the premium is greater than the minimum premium, it computes the emission rate and nominal emissions
        if (premium >= minimumPremium) {
            emissionRate = (baseEmissionRate * premium) / minimumPremium; // in OHM scale
            supplyToAdd = (getSupply() * emissionRate) / 10 ** _ohmDecimals; // OHM Scale * OHM Scale / OHM Scale = OHM Scale

            // It then logs this information for future use
            sales.push(Sale(premium, emissionRate, supplyToAdd, 0));
            saleCounter++;
        }

        // Before returning the number of tokens to sell
        return supplyToAdd;
    }

    /// @notice create bond protocol market with given budget
    /// @param saleAmount amount of DAI to fund bond market with
    function _createMarket(uint256 saleAmount) internal {
        // Calculate scaleAdjustment for bond market
        // Price decimals are returned from the perspective of the quote token
        // so the operations assume payoutPriceDecimal is zero and quotePriceDecimals
        // is the priceDecimal value
        uint256 minPrice = (minimumPremium * backing) / 10 ** _reserveDecimals;
        int8 priceDecimals = _getPriceDecimals(minPrice);
        int8 scaleAdjustment = int8(_ohmDecimals) - int8(_reserveDecimals) + (priceDecimals / 2);

        // Calculate oracle scale and bond scale with scale adjustment and format prices for bond market
        uint256 oracleScale = 10 ** uint8(int8(_oracleDecimals) - priceDecimals);
        uint256 bondScale = 10 **
            uint8(
                36 + scaleAdjustment + int8(_reserveDecimals) - int8(_ohmDecimals) - priceDecimals
            );

        // Approve OHM on bond teller
        uint256 currentApproval = ohm.allowance(address(this), address(teller));
        ohm.approve(address(teller), currentApproval + saleAmount);

        // Create new bond market to buy the reserve with OHM
        uint256 marketId = auctioneer.createMarket(
            abi.encode(
                IBondSDA.MarketParams({
                    payoutToken: ohm,
                    quoteToken: dai,
                    callbackAddr: address(0),
                    capacityInQuote: false,
                    capacity: saleAmount,
                    formattedInitialPrice: PRICE.getLastPrice().mulDiv(bondScale, oracleScale),
                    formattedMinimumPrice: minPrice.mulDiv(bondScale, oracleScale),
                    debtBuffer: 100_000, // 100%
                    vesting: vestingPeriod,
                    conclusion: uint48(block.timestamp + 1 days), // 1 day from now
                    depositInterval: uint32(4 hours), // 4 hours
                    scaleAdjustment: scaleAdjustment
                })
            )
        );

        emit SaleCreated(marketId, saleAmount);
    }

    /// @notice allow emission manager to update backing price based on new supply and reserves added
    /// @param supplyAdded number of new OHM minted
    /// @param reservesAdded number of new DAI added
    function _updateBacking(uint256 supplyAdded, uint256 reservesAdded) internal {
        uint256 previousReserves = getReserves() - reservesAdded;
        uint256 previousSupply = getSupply() - supplyAdded;

        uint256 percentIncreaseReserves = (reservesAdded * 10 ** _reserveDecimals) /
            previousReserves;
        uint256 percentIncreaseSupply = (supplyAdded * 10 ** _reserveDecimals) / previousSupply; // scaled to 1e18 to match

        backing =
            (backing * percentIncreaseReserves) / // price multiplied by percent increase reserves in reserve scale
            percentIncreaseSupply; // divided by percent increase supply in reserve scale
    }

    /// @notice         Helper function to calculate number of price decimals based on the value returned from the price feed.
    /// @param price_   The price to calculate the number of decimals for
    /// @return         The number of decimals
    function _getPriceDecimals(uint256 price_) internal view returns (int8) {
        int8 decimals;
        while (price_ >= 10) {
            price_ = price_ / 10;
            decimals++;
        }

        // Subtract the stated decimals from the calculated decimals to get the relative price decimals.
        // Required to do it this way vs. normalizing at the beginning since price decimals can be negative.
        return decimals - int8(_oracleDecimals);
    }

    // ========== ADMIN FUNCTIONS ========== //

    function shutdown() external onlyRole("emergency_shutdown") {
        locallyActive = false;
        shutdownTimestamp = uint48(block.timestamp);

        uint256 ohmBalance = ohm.balanceOf(address(this));
        if (ohmBalance > 0) BurnableERC20(address(ohm)).burn(ohmBalance);

        uint256 daiBalance = dai.balanceOf(address(this));
        if (daiBalance > 0) sdai.deposit(daiBalance, address(TRSRY));
    }

    function restart() external onlyRole("emergency_restart") {
        // Restart can be activated only within the specified timeframe since shutdown
        // Outside of this span of time, emissions_admin must reinitialize
        if (uint48(block.timestamp) < shutdownTimestamp + restartTimeframe) locallyActive = true;
    }

    /// @notice set the base emissions rate
    /// @param changeBy_ uint256 added or subtracted from baseEmissionRate
    /// @param forNumBeats_ uint256 number of times to change baseEmissionRate by changeBy_
    /// @param add bool determining addition or subtraction to baseEmissionRate
    function changeBaseRate(
        uint256 changeBy_,
        uint48 forNumBeats_,
        bool add
    ) external onlyRole("emissions_admin") {
        if (!add && (changeBy_ * forNumBeats_ > baseEmissionRate)) revert("Math will underflow");
        rateChange = BaseRateChange(changeBy_, forNumBeats_, add);
    }

    /// @notice set the minimum premium for emissions
    /// @param newMinimumPremium_ uint256
    function setMinimumPremium(uint256 newMinimumPremium_) external onlyRole("emissions_admin") {
        minimumPremium = newMinimumPremium_;
    }

    /// @notice set the new vesting period in seconds
    /// @param newVestingPeriod_ uint48
    function setVestingPeriod(uint48 newVestingPeriod_) external onlyRole("emissions_admin") {
        vestingPeriod = newVestingPeriod_;
    }

    /// @notice allow governance to adjust backing price if deviated from reality
    /// @dev note if adjustment is more than 33% down, contract should be redeployed
    /// @param newBacking to adjust to
    /// TODO maybe put in a timespan arg so it can be smoothed over time if desirable
    function adjustBacking(uint256 newBacking) external onlyRole("emissions_admin") {
        if (newBacking < (backing * 9) / 10) revert("Change too significant");
        backing = newBacking;
    }

    /// @notice allow governance to adjust the timeframe for restart after shutdown
    /// @param newTimeframe to adjust it to
    function adjustRestartTimeframe(uint48 newTimeframe) external onlyRole("emissions_admin") {
        restartTimeframe = newTimeframe;
    }

    function updateBondContracts(
        address auctioneer_,
        address teller_
    ) external onlyRole("emissions_admin") {
        if (auctioneer_ == address(0)) revert("Auctioneer address cannot be 0");
        if (teller_ == address(0)) revert("Teller address cannot be 0");

        auctioneer = IBondSDA(auctioneer_);
        teller = teller_;
    }

    // =========- VIEW FUNCTIONS ========== //

    /// @notice return reserves, measured as clearinghouse receivables and sdai balances, in DAI denomination
    function getReserves() public view returns (uint256 reserves) {
        uint256 chCount = CHREG.registryCount();
        for (uint256 i; i < chCount; i++) {
            reserves += Clearinghouse(CHREG.registry(i)).principalReceivables();
            uint256 bal = sdai.balanceOf(CHREG.registry(i));
            if (bal > 0) reserves += sdai.previewRedeem(bal);
        }

        reserves += sdai.previewRedeem(sdai.balanceOf(address(TRSRY)));
    }

    /// @notice return supply, measured as supply of gOHM in OHM denomination
    function getSupply() public view returns (uint256 supply) {
        return (gohm.totalSupply() * gohm.index()) / 10 ** _ohmDecimals;
    }

    function getPremium() public view returns (uint256) {
        uint256 price = PRICE.getLastPrice();
        return (price * 10 ** _reserveDecimals) / backing;
    }

    function nextSale() public view returns (uint256 emissionRate, uint256 supplyToAdd) {
        // To calculate the sale, it first computes premium (market price / backing price)
        uint256 price = PRICE.getLastPrice();
        uint256 premium = (price * 10 ** _reserveDecimals) / backing;

        // If the premium is greater than the minimum premium, it computes the emission rate and nominal emissions
        if (premium >= minimumPremium) {
            emissionRate = (baseEmissionRate * premium) / minimumPremium; // in OHM scale
            supplyToAdd = (getSupply() * emissionRate) / 10 ** _ohmDecimals; // OHM Scale * OHM Scale / OHM Scale = OHM Scale
        }
    }
}
