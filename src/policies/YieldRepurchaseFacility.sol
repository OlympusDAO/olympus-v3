// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {TransferHelper} from "libraries/TransferHelper.sol";
import {FullMath} from "libraries/FullMath.sol";

// Interfaces
import {IBondSDA} from "interfaces/IBondSDA.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {IYieldRepo} from "policies/interfaces/IYieldRepo.sol";

// Bophades
import {Kernel, Policy, Permissions, Keycode, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {PRICEv1} from "modules/PRICE/PRICE.v1.sol";
import {CHREGv1} from "modules/CHREG/CHREG.v1.sol";
import {CDEPOv1} from "modules/CDEPO/CDEPO.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

interface BurnableERC20 {
    function burn(uint256 amount) external;
}

/// @notice the Yield Repurchase Facility (Yield Repo) contract pulls a derived amount of yield from
///         the Olympus treasury each week and uses it, along with the backing of previously purchased
///         OHM, to purchase OHM off the market using a Bond Protocol SDA market.
contract YieldRepurchaseFacility is IYieldRepo, Policy, PolicyEnabler {
    using FullMath for uint256;
    using TransferHelper for ERC20;

    ///////////////////////// CONSTANTS /////////////////////////

    /// @notice The length of the epoch
    /// @dev    3 epochs per day, 7 days = 21
    uint48 public constant epochLength = 21;

    /// @notice The backing per token
    /// @dev    Assume backing of $11.33
    uint256 public constant backingPerToken = 1133 * 1e7;

    /// @notice The role assigned to the Heart contract
    ///         This enables the Heart contract to call specific functions on this contract
    bytes32 public constant ROLE_HEART = "heart";

    /// @notice The length of the `EnableParams` struct in bytes
    uint256 internal constant ENABLE_PARAMS_LENGTH = 96;

    ///////////////////////// STATE /////////////////////////

    // Tokens
    // solhint-disable immutable-vars-naming
    ERC4626 public immutable sReserve;
    ERC20 public immutable reserve;
    uint8 internal immutable _reserveDecimals;
    ERC20 public immutable ohm;
    uint8 internal immutable _ohmDecimals; // = 9;
    uint8 internal _oracleDecimals;

    // Modules
    TRSRYv1 public TRSRY;
    PRICEv1 public PRICE;
    CHREGv1 public CHREG;
    CDEPOv1 public CDEPO;

    // External contracts
    address public immutable teller; // = 0x007F7735baF391e207E3aA380bb53c4Bd9a5Fed6;
    IBondSDA public immutable auctioneer; // = IBondSDA(0x007F7A1cb838A872515c8ebd16bE4b14Ef43a222);

    // System variables
    uint48 public epoch; // a running counter to keep time
    uint256 public nextYield; // the amount of reserve to pull as yield at the start of the next week
    uint256 public lastReserveBalance; // the sReserve balance, in reserve units, at the end of the last week
    uint256 public lastConversionRate; // the sReserve conversion rate at the end of the last week

    // we use this to compute yield accrued
    // yield = last reserve balance * ((current conversion rate / last conversion rate) - 1)
    //       + current clearinghouse principal receivables * clearinghouse APR / 52 weeks

    ///////////////////////// SETUP /////////////////////////

    constructor(
        Kernel kernel_,
        address ohm_,
        address sReserve_,
        address teller_,
        address auctioneer_
    ) Policy(kernel_) {
        // Set immutable variables
        ohm = ERC20(ohm_);
        sReserve = ERC4626(sReserve_);
        reserve = ERC20(sReserve.asset());
        teller = teller_;
        auctioneer = IBondSDA(auctioneer_);

        // Cache token decimals
        _reserveDecimals = reserve.decimals();
        _ohmDecimals = ohm.decimals();

        // Disabled by default
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](5);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("PRICE");
        dependencies[2] = toKeycode("CHREG");
        dependencies[3] = toKeycode("ROLES");
        dependencies[4] = toKeycode("CDEPO");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        PRICE = PRICEv1(getModuleAddress(dependencies[1]));
        CHREG = CHREGv1(getModuleAddress(dependencies[2]));
        ROLES = ROLESv1(getModuleAddress(dependencies[3]));
        CDEPO = CDEPOv1(getModuleAddress(dependencies[4]));

        _oracleDecimals = PRICE.decimals();
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();

        permissions = new Permissions[](2);
        permissions[0] = Permissions(TRSRY_KEYCODE, TRSRYv1.withdrawReserves.selector);
        permissions[1] = Permissions(TRSRY_KEYCODE, TRSRYv1.increaseWithdrawApproval.selector);
    }

    /// @notice Returns the version of the policy.
    ///
    /// @return major The major version of the policy.
    /// @return minor The minor version of the policy.
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 3);
    }

    ///////////////////////// EXTERNAL /////////////////////////

    /// @notice create a new bond market at the end of the day with some portion of remaining funds
    function endEpoch() public override onlyRole(ROLE_HEART) {
        if (!isEnabled) return; // disabling this contract will not interfere with heartbeat
        epoch++;

        if (epoch % 3 != 0) return; // only execute once per day
        if (epoch == epochLength) {
            // reset at end of week
            epoch = 0;
            _withdraw(nextYield);

            nextYield = getNextYield();
            emit NextYieldSet(nextYield);
            lastConversionRate = sReserve.previewRedeem(1e18);
            lastReserveBalance = getReserveBalance();
        }

        _getBackingForPurchased(); // convert yesterdays ohm purchases into sReserve

        uint256 reserveBalance = reserve.balanceOf(address(this));
        uint256 totalBalanceInReserve = reserveBalance +
            sReserve.previewRedeem(sReserve.balanceOf(address(this)));

        // use portion of reserve balance based on day of the week
        // i.e. day one, use 1/7th; day two, use 1/6th; 1/5th; 1/4th; ...
        uint256 bidAmount = totalBalanceInReserve / (7 - (epoch / 3));

        // contract holds funds in sReserve except for the day's inventory, so we need to redeem before opening a market
        uint256 bidAmountFromSReserve = reserveBalance < bidAmount
            ? bidAmount - reserve.balanceOf(address(this))
            : 0;
        if (bidAmountFromSReserve != 0)
            sReserve.redeem(
                sReserve.previewWithdraw(bidAmountFromSReserve),
                address(this),
                address(this)
            );

        _createMarket(bidAmount);
    }

    /// @notice allow manager to increase (by maximum 10%) or decrease yield for week if contract is inaccurate
    /// @param newNextYield to fund
    function adjustNextYield(uint256 newNextYield) external onlyAdminRole {
        if (newNextYield > nextYield && ((newNextYield * 1e18) / nextYield) > (11 * 1e17))
            revert TooMuchIncrease();

        nextYield = newNextYield;
        emit NextYieldSet(nextYield);
    }

    ///////////////////////// ENABLE/DISABLE /////////////////////////

    /// @inheritdoc PolicyEnabler
    /// @dev        This function expects the parameters to be an abi-encoded `address[]` with the tokens to transfer
    function _enable(bytes calldata params_) internal override {
        // Validate that the params are of the correct length
        if (params_.length != ENABLE_PARAMS_LENGTH) revert InvalidParam("params length");

        // Decode the params
        EnableParams memory params = abi.decode(params_, (EnableParams));

        // Initialize system variables
        epoch = 20;
        lastReserveBalance = params.initialReserveBalance;
        lastConversionRate = params.initialConversionRate;
        nextYield = params.initialYield;
        emit NextYieldSet(params.initialYield);
    }

    /// @inheritdoc PolicyEnabler
    /// @dev        This function expects the parameters to be an abi-encoded `address[]` with the tokens to transfer
    function _disable(bytes calldata params_) internal override {
        // Decode the params
        address[] memory tokensToTransfer = abi.decode(params_, (address[]));

        // Burn OHM in contract
        BurnableERC20(address(ohm)).burn(ohm.balanceOf(address(this)));

        // Transfer all tokens to treasury
        for (uint256 i; i < tokensToTransfer.length; i++) {
            ERC20 token = ERC20(tokensToTransfer[i]);
            token.safeTransfer(address(TRSRY), token.balanceOf(address(this)));
        }
    }

    ///////////////////////// INTERNAL /////////////////////////

    /// @notice create bond protocol market with given budget
    /// @param bidAmount amount of reserve to fund bond market with
    function _createMarket(uint256 bidAmount) internal {
        // Calculate inverse prices from the oracle feed
        // The start price is the current market price, which is also the last price since this is called on a heartbeat
        // The min price is the inverse of the maximum price of OHM in USDS
        uint256 minPrice = 0; // Min price of zero means max price of infinity -- no cap
        uint256 initialPrice = 10 ** (_oracleDecimals * 2) / ((PRICE.getLastPrice() * 97) / 100); // 3% below current stated price in case oracle is stale

        // Calculate scaleAdjustment for bond market
        // Price decimals are returned from the perspective of the quote token
        // so the operations assume payoutPriceDecimal is zero and quotePriceDecimals
        // is the priceDecimal value
        int8 priceDecimals = _getPriceDecimals(initialPrice);
        int8 scaleAdjustment = int8(_reserveDecimals) - int8(_ohmDecimals) + (priceDecimals / 2);

        // Calculate oracle scale and bond scale with scale adjustment and format prices for bond market
        uint256 oracleScale = 10 ** uint8(int8(_oracleDecimals) - priceDecimals);
        uint256 bondScale = 10 **
            uint8(
                36 + scaleAdjustment + int8(_ohmDecimals) - int8(_reserveDecimals) - priceDecimals
            );

        // Approve reserve on the bond teller
        reserve.safeApprove(address(teller), bidAmount);

        // Create new bond market to buy OHM with the reserve
        uint256 marketId = auctioneer.createMarket(
            abi.encode(
                IBondSDA.MarketParams({
                    payoutToken: reserve,
                    quoteToken: ohm,
                    callbackAddr: address(0),
                    capacityInQuote: false,
                    capacity: bidAmount,
                    formattedInitialPrice: initialPrice.mulDiv(bondScale, oracleScale),
                    formattedMinimumPrice: minPrice,
                    debtBuffer: 100_000, // 100%
                    vesting: uint48(0), // Instant swaps
                    conclusion: uint48(block.timestamp + 1 days), // 1 day from now
                    depositInterval: uint32(4 hours), // 4 hours
                    scaleAdjustment: scaleAdjustment
                })
            )
        );

        emit RepoMarket(marketId, bidAmount);
    }

    /// @notice internal function to burn ohm and retrieve backing
    function _getBackingForPurchased() internal {
        // Get backing for purchased OHM
        (uint256 ohmBalance, uint256 backing) = getOhmBalanceAndBacking();

        // Burn OHM in contract
        BurnableERC20(address(ohm)).burn(ohmBalance);

        // Withdraw backing for purchased ohm
        _withdraw(backing);
    }

    /// @notice internal function to withdraw sReserve from treasury
    /// @dev note amount given is in reserve, not sReserve
    /// @param amount an amount to withdraw, in reserve
    function _withdraw(uint256 amount) internal {
        // Get the amount of sReserve to withdraw
        uint256 amountInSReserve = sReserve.previewWithdraw(amount);

        // Approve and withdraw sReserve from TRSRY
        TRSRY.increaseWithdrawApproval(address(this), ERC20(address(sReserve)), amountInSReserve);
        TRSRY.withdrawReserves(address(this), ERC20(address(sReserve)), amountInSReserve);
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

    ///////////////////////// VIEW /////////////////////////

    /// @notice fetch combined sReserve balance of active clearinghouses and treasury, in reserve
    function getReserveBalance() public view override returns (uint256 balance) {
        // TRSRY
        uint256 sBalance = sReserve.balanceOf(address(TRSRY));

        // Clearinghouses
        uint256 len = CHREG.activeCount();
        for (uint256 i; i < len; i++) {
            sBalance += sReserve.balanceOf(CHREG.active(i));
        }

        // CDEPO
        sBalance += sReserve.balanceOf(address(CDEPO));

        balance = sReserve.previewRedeem(sBalance);
    }

    /// @notice compute yield for the next week
    function getNextYield() public view override returns (uint256 yield) {
        // add sReserve rewards accrued for week
        yield +=
            ((lastReserveBalance * sReserve.previewRedeem(1e18)) / lastConversionRate) -
            lastReserveBalance;
        // add clearinghouse interest accrued for week (0.5% divided by 52 weeks)
        // iterate through clearinghouses in the CHREG and get the outstanding principal receivables
        uint256 receivables;
        uint256 len = CHREG.registryCount();
        for (uint256 i; i < len; i++) {
            receivables += IGenericClearinghouse(CHREG.registry(i)).principalReceivables();
        }

        yield += (receivables * 5) / 1000 / 52;
    }

    /// @notice compute backing for ohm balance
    function getOhmBalanceAndBacking()
        public
        view
        override
        returns (uint256 balance, uint256 backing)
    {
        // balance and backingPerToken are 9 decimals, reserve amount is 18 decimals
        balance = ohm.balanceOf(address(this));
        backing = balance * backingPerToken;
    }
}
