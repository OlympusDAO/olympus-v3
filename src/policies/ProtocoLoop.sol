// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";
import {FullMath} from "libraries/FullMath.sol";

import {IBondSDA} from "interfaces/IBondSDA.sol";

import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {PRICEv1} from "modules/PRICE/PRICE.v1.sol";
import {RANGEv2} from "modules/RANGE/RANGE.v2.sol";

interface BurnableERC20 {
    function burn(uint256 amount) external;
}

interface Clearinghouse {
    function principalReceivables() external view returns (uint256);
}

/// @notice the ProtocoLoop contract pulls a derived amount of yield from the Olympus treasury each week
///         and uses it, along with the backing of previously purchased OHM, to purchase OHM off the
///         market using a Bond Protocol SDA market.
contract Protocoloop is Policy, RolesConsumer {
    using FullMath for uint256;
    using TransferHelper for ERC20;

    ///////////////////////// EVENTS /////////////////////////

    event ProtocolLoop(uint256 marketId, uint256 bidAmount);

    ///////////////////////// STATE /////////////////////////

    // Tokens
    ERC4626 public constant sdai = ERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
    ERC20 public constant dai = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    uint8 internal constant _daiDecimals = 18;
    ERC20 public immutable ohm = ERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
    uint8 internal constant _ohmDecimals = 9;
    uint8 internal _oracleDecimals;

    // Modules
    TRSRYv1 public TRSRY;
    PRICEv1 public PRICE;
    RANGEv2 public RANGE;

    // Policies
    Clearinghouse public immutable clearinghouse =
        Clearinghouse(0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c);

    // External contracts
    address public immutable teller = 0x007F7735baF391e207E3aA380bb53c4Bd9a5Fed6;
    IBondSDA public immutable auctioneer = IBondSDA(0x007F7A1cb838A872515c8ebd16bE4b14Ef43a222);

    // System variables
    uint48 public epoch; // a running counter to keep time
    uint256 public nextYield; // the amount of DAI to pull as yield at the start of the next week
    uint256 public lastReserveBalance; // the SDAI reserve balance, in DAI, at the end of the last week
    uint256 public lastConversionRate; // the SDAI conversion rate at the end of the last week
    // we use this to compute yield accrued
    // yield = last reserve balance * ((current conversion rate / last conversion rate) - 1)
    bool public isShutdown;

    // Constants
    uint48 public constant epochLength = 21; // one week
    uint256 public constant backingPerToken = 114 * 1e8; // assume backing of $11.40, TODO could use PRICE.minimumTargetPrice(), which is in theory set to LB

    ///////////////////////// SETUP /////////////////////////

    constructor(
        Kernel kernel,
        uint256 initialReserveBalance,
        uint256 initialConversionRate
    ) Policy(kernel) {
        epoch = 20;
        lastReserveBalance = initialReserveBalance;
        lastConversionRate = initialConversionRate;
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("PRICE");
        dependencies[2] = toKeycode("RANGE");
        dependencies[3] = toKeycode("ROLES");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        PRICE = PRICEv1(getModuleAddress(dependencies[1]));
        RANGE = RANGEv2(getModuleAddress(dependencies[2]));
        ROLES = ROLESv1(getModuleAddress(dependencies[3]));

        _oracleDecimals = PRICE.decimals();
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();

        permissions = new Permissions[](3);
        permissions[0] = Permissions(TRSRY_KEYCODE, TRSRYv1.withdrawReserves.selector);
        permissions[1] = Permissions(TRSRY_KEYCODE, TRSRYv1.increaseWithdrawApproval.selector);
    }

    ///////////////////////// EXTERNAL /////////////////////////

    /// @notice create a new bond market at the end of the day with some portion of remaining funds
    function endEpoch() public onlyRole("heart") {
        if (isShutdown) return; // disabling this contract will not interfere with heartbeat
        epoch++;

        if (epoch % 3 != 0) return; // only execute once per day
        if (epoch == epochLength) {
            // reset at end of week
            epoch = 0;
            _withdraw(nextYield);

            nextYield = getNextYield();
            lastConversionRate = sdai.previewRedeem(1e18);
            lastReserveBalance = getReserveBalance();
        }

        _getBackingForPurchased(); // convert yesterdays ohm purchases into sdai

        uint256 balanceInDAI = dai.balanceOf(address(this)) +
            sdai.previewRedeem(sdai.balanceOf(address(this)));
        // use portion of dai balance based on day of the week
        // i.e. day one, use 1/7th; day two, use 1/6th; 1/5th; 1/4th; ...
        uint256 bidAmount = balanceInDAI / (7 - (epoch / 3));

        // contract holds funds in sDAI except for the day's inventory, so we need to redeem before opening a market
        sdai.redeem(sdai.convertToShares(bidAmount), address(this), address(this));

        _createMarket(bidAmount);
    }

    /// @notice allow manager to increase (by maximum 10%) or decrease yield for week if contract is inaccurate
    /// @param newNextYield to fund
    function adjustNextYield(uint256 newNextYield) external onlyRole("loop_daddy") {
        if (newNextYield > nextYield && ((newNextYield * 1e18) / nextYield) > (11 * 1e17))
            revert("Too much increase");

        nextYield = newNextYield;
    }

    /// @notice retire contract by burning ohm balance and transferring tokens to treasury
    /// @param tokensToTransfer list of tokens to transfer back to treasury (i.e. DAI)
    function shutdown(ERC20[] memory tokensToTransfer) external onlyRole("loop_daddy") {
        isShutdown = true;

        // Burn OHM in contract
        BurnableERC20(address(ohm)).burn(ohm.balanceOf(address(this)));

        // Transfer all tokens to treasury
        for (uint256 i; i < tokensToTransfer.length; i++) {
            ERC20 token = tokensToTransfer[i];
            token.safeTransfer(address(TRSRY), token.balanceOf(address(this)));
        }
    }

    ///////////////////////// INTERNAL /////////////////////////

    /// @notice create bond protocol market with given budget
    /// @param bidAmount amount of DAI to fund bond market with
    function _createMarket(uint256 bidAmount) internal {
        // Calculate inverse prices from the oracle feed
        // The start price is the current market price, which is also the last price since this is called on a heartbeat
        // The min price is the upper cushion price, since we don't want to buy above this level
        uint256 minPrice = 10 ** (_oracleDecimals * 2) / RANGE.price(true, false); // upper cushion = (true, false) => high = true, wall = false
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
        dai.safeApprove(address(teller), bidAmount);

        // Create new bond market to buy OHM with the reserve
        uint256 marketId = auctioneer.createMarket(
            abi.encode(
                IBondSDA.MarketParams({
                    payoutToken: dai,
                    quoteToken: ohm,
                    callbackAddr: address(0),
                    capacityInQuote: false,
                    capacity: bidAmount,
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

        emit ProtocolLoop(marketId, bidAmount);
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

    /// @notice internal function to burn ohm and retrieve backing
    function _getBackingForPurchased() internal {
        uint256 balance = ohm.balanceOf(address(this));
        uint256 backingForBalance = balance * backingPerToken; // balance and backingPerToken are 9 decimals, dai amount is 18 decimals

        // Burn OHM in contract
        BurnableERC20(address(ohm)).burn(balance);

        // Withdraw backing for purchased ohm
        _withdraw(backingForBalance);
    }

    /// @notice internal function to withdraw sDAI from treasury
    /// @dev note amount given is in DAI, not sDAI
    /// @param amount an amount to withdraw, in DAI
    function _withdraw(uint256 amount) internal {
        // Get the amount of sDAI to withdraw
        uint256 amountInSDAI = sdai.previewWithdraw(amount);

        // Approve and withdraw sDAI from TRSRY
        TRSRY.increaseWithdrawApproval(address(this), ERC20(address(sdai)), amountInSDAI);
        TRSRY.withdrawReserves(address(this), ERC20(address(sdai)), amountInSDAI);
    }

    ///////////////////////// VIEW /////////////////////////

    /// @notice fetch combined sdai balance of clearinghouse and treasury, in DAI
    function getReserveBalance() public view returns (uint256 balance) {
        uint256 sBalance = sdai.balanceOf(address(clearinghouse));
        sBalance += sdai.balanceOf(address(TRSRY));

        balance = sdai.previewRedeem(sBalance);
    }

    /// @notice compute yield for the next week
    function getNextYield() public view returns (uint256 yield) {
        // add sDAI rewards accrued for week
        yield +=
            ((lastReserveBalance * sdai.previewRedeem(1e18)) / lastConversionRate) -
            getReserveBalance();
        // add clearinghouse interest accrued for week (0.5% divided by 52 weeks)
        yield += (clearinghouse.principalReceivables() * 5) / 1000 / 52;
    }
}
