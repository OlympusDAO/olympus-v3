// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {TransferHelper} from "libraries/TransferHelper.sol";

import {FullMath} from "libraries/FullMath.sol";

import {IBondSDA} from "interfaces/IBondSDA.sol";
import {IgOHM} from "interfaces/IgOHM.sol";

import {RolesConsumer, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {PRICEv1} from "modules/PRICE/PRICE.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {CHREGv1} from "modules/CHREG/CHREG.v1.sol";

import {IEmissionManager} from "policies/interfaces/IEmissionManager.sol";
import {CDAuctioneer} from "./CDAuctioneer.sol";

interface BurnableERC20 {
    function burn(uint256 amount) external;
}

interface Clearinghouse {
    function principalReceivables() external view returns (uint256);
}

// solhint-disable max-states-count
contract EmissionManager is IEmissionManager, Policy, RolesConsumer {
    using FullMath for uint256;
    using TransferHelper for ERC20;

    // ========== STATE VARIABLES ========== //

    /// @notice active base emissions rate change information
    /// @dev active until daysLeft is 0
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
    ERC20 public immutable reserve;
    ERC4626 public immutable sReserve;

    // External contracts
    IBondSDA public bondAuctioneer;
    address public teller;
    CDAuctioneer public cdAuctioneer;

    // Manager variables
    uint256 public baseEmissionRate;
    uint256 public minimumPremium;
    uint48 public vestingPeriod; // initialized at 0
    uint256 public backing;
    uint8 public beatCounter;
    bool public locallyActive;
    uint256 public activeMarketId;
    uint256 public tickSizeScalar;
    uint256 public minPriceScalar;

    uint8 internal _oracleDecimals;
    uint8 internal immutable _ohmDecimals;
    uint8 internal immutable _gohmDecimals;
    uint8 internal immutable _reserveDecimals;

    /// @notice timestamp of last shutdown
    uint48 public shutdownTimestamp;
    /// @notice time in seconds that the manager needs to be restarted after a shutdown, otherwise it must be re-initialized
    uint48 public restartTimeframe;

    uint256 internal constant ONE_HUNDRED_PERCENT = 1e18;

    // ========== ERRORS ========== //

    error EmissionManager_InvalidParams(string reason);

    // ========== SETUP ========== //

    constructor(
        Kernel kernel_,
        address ohm_,
        address gohm_,
        address reserve_,
        address sReserve_,
        address bondAuctioneer_,
        address cdAuctioneer_,
        address teller_
    ) Policy(kernel_) {
        // Set immutable variables
        if (ohm_ == address(0)) revert EmissionManager_InvalidParams("OHM address cannot be 0");
        if (gohm_ == address(0)) revert EmissionManager_InvalidParams("gOHM address cannot be 0");
        if (reserve_ == address(0)) revert EmissionManager_InvalidParams("DAI address cannot be 0");
        if (sReserve_ == address(0))
            revert EmissionManager_InvalidParams("sDAI address cannot be 0");
        if (bondAuctioneer_ == address(0))
            revert EmissionManager_InvalidParams("Bond Auctioneer address cannot be 0");
        if (cdAuctioneer_ == address(0))
            revert EmissionManager_InvalidParams("CD Auctioneer address cannot be 0");

        ohm = ERC20(ohm_);
        gohm = IgOHM(gohm_);
        reserve = ERC20(reserve_);
        sReserve = ERC4626(sReserve_);
        bondAuctioneer = IBondSDA(bondAuctioneer_);
        cdAuctioneer = CDAuctioneer(cdAuctioneer_);
        teller = teller_;

        _ohmDecimals = ohm.decimals();
        _gohmDecimals = ERC20(gohm_).decimals();
        _reserveDecimals = reserve.decimals();

        // Max approve sReserve contract for reserve for deposits
        reserve.approve(address(sReserve), type(uint256).max);
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

    /// @inheritdoc IEmissionManager
    function execute() external onlyRole("heart") {
        if (!locallyActive) return;

        beatCounter = ++beatCounter % 3;
        if (beatCounter != 0) return;

        if (rateChange.daysLeft != 0) {
            --rateChange.daysLeft;
            if (rateChange.addition) baseEmissionRate += rateChange.changeBy;
            else baseEmissionRate -= rateChange.changeBy;
        }

        // It then calculates the amount to sell for the coming day
        (, , uint256 emission) = getNextEmission();

        uint256 remainder = cdAuctioneer.beat(
            emission,
            getSizeFor(emission),
            getMinPriceFor(PRICE.getCurrentPrice())
        );

        // And then opens a market if applicable
        if (remainder != 0) {
            MINTR.increaseMintApproval(address(this), remainder);
            _createMarket(remainder);
        }
    }

    // ========== INITIALIZE ========== //

    /// @notice allow governance to initialize the emission manager
    /// @param baseEmissionsRate_ percent of OHM supply to issue per day at the minimum premium, in OHM scale, i.e. 1e9 = 100%
    /// @param minimumPremium_ minimum premium at which to issue OHM, a percentage where 1e18 is 100%
    /// @param backing_ backing price of OHM in reserve token, in reserve scale
    /// @param restartTimeframe_ time in seconds that the manager needs to be restarted after a shutdown, otherwise it must be re-initialized
    function initialize(
        uint256 baseEmissionsRate_,
        uint256 minimumPremium_,
        uint256 backing_,
        uint256 tickScalar,
        uint256 priceScalar,
        uint48 restartTimeframe_
    ) external onlyRole("emissions_admin") {
        // Cannot initialize if currently active
        if (locallyActive) revert AlreadyActive();

        // Cannot initialize if the restart timeframe hasn't passed since the shutdown timestamp
        // This is specific to re-initializing after a shutdown
        // It will not revert on the first initialization since both values will be zero
        if (shutdownTimestamp + restartTimeframe > uint48(block.timestamp))
            revert CannotRestartYet(shutdownTimestamp + restartTimeframe);

        // Validate inputs
        if (baseEmissionsRate_ == 0) revert InvalidParam("baseEmissionRate");
        if (minimumPremium_ == 0) revert InvalidParam("minimumPremium");
        if (backing_ == 0) revert InvalidParam("backing");
        if (restartTimeframe_ == 0) revert InvalidParam("restartTimeframe");
        if (tickScalar == 0 || tickScalar > ONE_HUNDRED_PERCENT)
            revert InvalidParam("Tick Size Scalar");
        if (priceScalar == 0 || priceScalar > ONE_HUNDRED_PERCENT)
            revert InvalidParam("Tick Size Scalar");

        // Assign
        baseEmissionRate = baseEmissionsRate_;
        minimumPremium = minimumPremium_;
        backing = backing_;
        restartTimeframe = restartTimeframe_;
        tickSizeScalar = tickScalar;
        minPriceScalar = priceScalar;

        // Activate
        locallyActive = true;

        emit Activated();
        emit MinimumPremiumChanged(minimumPremium_);
        emit BackingChanged(backing_);
        emit RestartTimeframeChanged(restartTimeframe_);
    }

    // ========== BOND CALLBACK ========== //

    /// @notice callback function for bond market, only callable by the teller
    function callback(uint256 id_, uint256 inputAmount_, uint256 outputAmount_) external {
        // Only callable by the bond teller
        if (msg.sender != teller) revert OnlyTeller();

        // Market ID must match the active market ID stored locally, otherwise revert
        if (id_ != activeMarketId) revert InvalidMarket();

        // Reserve balance should have increased by atleast the input amount
        uint256 reserveBalance = reserve.balanceOf(address(this));
        if (reserveBalance < inputAmount_) revert InvalidCallback();

        // Update backing value with the new reserves added and supply added
        // We do this before depositing the received reserves and minting the output amount of OHM
        // so that the getReserves and getSupply values equal the "previous" values
        // This also conforms to the CEI pattern
        _updateBacking(outputAmount_, inputAmount_);

        // Deposit the reserve balance into the sReserve contract with the TRSRY as the recipient
        // This will sweep any excess reserves into the TRSRY as well
        sReserve.deposit(reserveBalance, address(TRSRY));

        // Mint the output amount of OHM to the Teller
        MINTR.mintOhm(teller, outputAmount_);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @notice create bond protocol market with given budget
    /// @param saleAmount amount of DAI to fund bond market with
    function _createMarket(uint256 saleAmount) internal {
        // Calculate scaleAdjustment for bond market
        // Price decimals are returned from the perspective of the quote token
        // so the operations assume payoutPriceDecimal is zero and quotePriceDecimals
        // is the priceDecimal value
        uint256 minPrice = ((ONE_HUNDRED_PERCENT + minimumPremium) * backing) /
            10 ** _reserveDecimals;
        int8 priceDecimals = _getPriceDecimals(minPrice);
        int8 scaleAdjustment = int8(_ohmDecimals) - int8(_reserveDecimals) + (priceDecimals / 2);

        // Calculate oracle scale and bond scale with scale adjustment and format prices for bond market
        uint256 oracleScale = 10 ** uint8(int8(_oracleDecimals) - priceDecimals);
        uint256 bondScale = 10 **
            uint8(
                36 + scaleAdjustment + int8(_reserveDecimals) - int8(_ohmDecimals) - priceDecimals
            );

        // Create new bond market to buy the reserve with OHM
        activeMarketId = bondAuctioneer.createMarket(
            abi.encode(
                IBondSDA.MarketParams({
                    payoutToken: ohm,
                    quoteToken: reserve,
                    callbackAddr: address(this),
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

        emit SaleCreated(activeMarketId, saleAmount);
    }

    /// @notice allow emission manager to update backing price based on new supply and reserves added
    /// @param supplyAdded number of new OHM minted
    /// @param reservesAdded number of new DAI added
    function _updateBacking(uint256 supplyAdded, uint256 reservesAdded) internal {
        uint256 previousReserves = getReserves();
        uint256 previousSupply = getSupply();

        uint256 percentIncreaseReserves = ((previousReserves + reservesAdded) *
            10 ** _reserveDecimals) / previousReserves;
        uint256 percentIncreaseSupply = ((previousSupply + supplyAdded) * 10 ** _reserveDecimals) /
            previousSupply; // scaled to reserve decimals to match

        backing =
            (backing * percentIncreaseReserves) / // price multiplied by percent increase reserves in reserve scale
            percentIncreaseSupply; // divided by percent increase supply in reserve scale

        // Emit event to track backing changes and results of sales offchain
        emit BackingUpdated(backing, supplyAdded, reservesAdded);
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

    /// @notice shutdown the emission manager locally and close the active bond market
    function shutdown() external onlyRole("emergency_shutdown") {
        locallyActive = false;
        shutdownTimestamp = uint48(block.timestamp);

        // Shutdown the bond market, if it is active
        if (bondAuctioneer.isLive(activeMarketId)) {
            bondAuctioneer.closeMarket(activeMarketId);
        }

        emit Deactivated();
    }

    /// @notice restart the emission manager locally
    function restart() external onlyRole("emergency_restart") {
        // Restart can be activated only within the specified timeframe since shutdown
        // Outside of this span of time, emissions_admin must reinitialize
        if (uint48(block.timestamp) >= shutdownTimestamp + restartTimeframe)
            revert RestartTimeframePassed();

        locallyActive = true;

        emit Activated();
    }

    /// @notice Rescue any ERC20 token sent to this contract and send it to the TRSRY
    /// @dev This function is restricted to the emissions_admin role
    /// @param token_ The address of the ERC20 token to rescue
    function rescue(address token_) external onlyRole("emissions_admin") {
        ERC20 token = ERC20(token_);
        token.safeTransfer(address(TRSRY), token.balanceOf(address(this)));
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
        // Prevent underflow on negative adjustments
        if (!add && (changeBy_ * forNumBeats_ > baseEmissionRate))
            revert InvalidParam("changeBy * forNumBeats");

        // Prevent overflow on positive adjustments
        if (add && (type(uint256).max - changeBy_ * forNumBeats_ < baseEmissionRate))
            revert InvalidParam("changeBy * forNumBeats");

        rateChange = BaseRateChange(changeBy_, forNumBeats_, add);

        emit BaseRateChanged(changeBy_, forNumBeats_, add);
    }

    /// @notice set the minimum premium for emissions
    /// @param newMinimumPremium_ uint256
    function setMinimumPremium(uint256 newMinimumPremium_) external onlyRole("emissions_admin") {
        if (newMinimumPremium_ == 0) revert InvalidParam("newMinimumPremium");

        minimumPremium = newMinimumPremium_;

        emit MinimumPremiumChanged(newMinimumPremium_);
    }

    /// @notice set the new vesting period in seconds
    /// @param newVestingPeriod_ uint48
    function setVestingPeriod(uint48 newVestingPeriod_) external onlyRole("emissions_admin") {
        // Verify that the vesting period isn't more than a year
        // This check helps ensure a timestamp isn't input instead of a duration
        if (newVestingPeriod_ > uint48(31536000)) revert InvalidParam("newVestingPeriod");
        vestingPeriod = newVestingPeriod_;

        emit VestingPeriodChanged(newVestingPeriod_);
    }

    /// @notice allow governance to adjust backing price if deviated from reality
    /// @dev note if adjustment is more than 33% down, contract should be redeployed
    /// @param newBacking to adjust to
    /// TODO maybe put in a timespan arg so it can be smoothed over time if desirable
    function setBacking(uint256 newBacking) external onlyRole("emissions_admin") {
        // Backing cannot be reduced by more than 10% at a time
        if (newBacking == 0 || newBacking < (backing * 9) / 10) revert InvalidParam("newBacking");
        backing = newBacking;

        emit BackingChanged(newBacking);
    }

    /// @notice allow governance to adjust the timeframe for restart after shutdown
    /// @param newTimeframe to adjust it to
    function setRestartTimeframe(uint48 newTimeframe) external onlyRole("emissions_admin") {
        // Restart timeframe must be greater than 0
        if (newTimeframe == 0) revert InvalidParam("newRestartTimeframe");

        restartTimeframe = newTimeframe;

        emit RestartTimeframeChanged(newTimeframe);
    }

    /// @notice allow governance to set the bond contracts used by the emission manager
    /// @param bondAuctioneer_ address of the bond auctioneer contract
    /// @param teller_ address of the bond teller contract
    function setBondContracts(
        address bondAuctioneer_,
        address teller_
    ) external onlyRole("emissions_admin") {
        // Bond contracts cannot be set to the zero address
        if (bondAuctioneer_ == address(0)) revert InvalidParam("bondAuctioneer");
        if (teller_ == address(0)) revert InvalidParam("teller");

        bondAuctioneer = IBondSDA(bondAuctioneer_);
        teller = teller_;

        emit BondContractsSet(bondAuctioneer_, teller_);
    }

    /// @notice allow governance to set the CD contract used by the emission manager
    /// @param cdAuctioneer_ address of the cd auctioneer contract
    function setCDAuctionContract(address cdAuctioneer_) external onlyRole("emissions_admin") {
        // Auction contract cannot be set to the zero address
        if (cdAuctioneer_ == address(0)) revert InvalidParam("cdAuctioneer");

        cdAuctioneer = CDAuctioneer(cdAuctioneer_);
    }

    /// @notice allow governance to set the CD tick size scalar
    /// @param newScalar as a percentage in 18 decimals
    function setTickSizeScalar(uint256 newScalar) external onlyRole("emissions_admin") {
        if (newScalar == 0 || newScalar > ONE_HUNDRED_PERCENT)
            revert InvalidParam("Tick Size Scalar");
        tickSizeScalar = newScalar;
    }

    /// @notice allow governance to set the CD minimum price scalar
    /// @param newScalar as a percentage in 18 decimals
    function setMinPriceScalar(uint256 newScalar) external onlyRole("emissions_admin") {
        if (newScalar == 0 || newScalar > ONE_HUNDRED_PERCENT)
            revert InvalidParam("Min Price Scalar");
        minPriceScalar = newScalar;
    }

    // =========- VIEW FUNCTIONS ========== //

    /// @notice return reserves, measured as clearinghouse receivables and sReserve balances, in reserve denomination
    function getReserves() public view returns (uint256 reserves) {
        uint256 chCount = CHREG.registryCount();
        for (uint256 i; i < chCount; i++) {
            reserves += Clearinghouse(CHREG.registry(i)).principalReceivables();
            uint256 bal = sReserve.balanceOf(CHREG.registry(i));
            if (bal > 0) reserves += sReserve.previewRedeem(bal);
        }

        reserves += sReserve.previewRedeem(sReserve.balanceOf(address(TRSRY)));
    }

    /// @notice return supply, measured as supply of gOHM in OHM denomination
    function getSupply() public view returns (uint256 supply) {
        return (gohm.totalSupply() * gohm.index()) / 10 ** _gohmDecimals;
    }

    /// @notice return the current premium as a percentage where 1e18 is 100%
    function getPremium() public view returns (uint256) {
        uint256 price = PRICE.getLastPrice();
        uint256 pbr = (price * 10 ** _reserveDecimals) / backing;
        return pbr > ONE_HUNDRED_PERCENT ? pbr - ONE_HUNDRED_PERCENT : 0;
    }

    /// @notice return the next sale amount, premium, emission rate, and emissions based on the current premium
    function getNextEmission()
        public
        view
        returns (uint256 premium, uint256 emissionRate, uint256 emission)
    {
        // To calculate the sale, it first computes premium (market price / backing price) - 100%
        premium = getPremium();

        // If the premium is greater than the minimum premium, it computes the emission rate and nominal emissions
        if (premium >= minimumPremium) {
            emissionRate =
                (baseEmissionRate * (ONE_HUNDRED_PERCENT + premium)) /
                (ONE_HUNDRED_PERCENT + minimumPremium); // in OHM scale
            emission = (getSupply() * emissionRate) / 10 ** _ohmDecimals; // OHM Scale * OHM Scale / OHM Scale = OHM Scale
        }
    }

    /// @notice get CD auction tick size for a given target
    /// @param  target size of day's CD auction
    /// @return size of tick
    function getSizeFor(uint256 target) public view returns (uint256) {
        return (target * tickSizeScalar) / ONE_HUNDRED_PERCENT;
    }

    /// @notice get CD auction minimum price for given current price
    /// @param  price of OHM on market according to PRICE module
    /// @return minPrice for CD auction
    function getMinPriceFor(uint256 price) public view returns (uint256) {
        return (price * minPriceScalar) / ONE_HUNDRED_PERCENT;
    }
}
