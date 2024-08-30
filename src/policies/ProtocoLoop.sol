// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface Clearinghouse {
    function principalReceivables() external view returns (uint256);
}

interface ISDAI is IERC20 {
    function convertToShares(uint256 assets) external view returns (uint256 shares);
    function convertToAssets(uint256 shares) external view returns (uint256 assets);
    function redeem(uint256 shares, address receiver, address owner) external;
}

interface Auctioneer {
    struct MarketParams {
        ERC20 payoutToken;
        ERC20 quoteToken;
        address callbackAddr;
        bool capacityInQuote;
        uint256 capacity;
        uint256 formattedInitialPrice;
        uint256 formattedMinimumPrice;
        uint32 debtBuffer;
        uint48 vesting;
        uint48 conclusion;
        uint32 depositInterval;
        int8 scaleAdjustment;
    }

    function createMarket(bytes memory params_) external returns (uint256);
}

/// @notice the ProtocoLoop contract pulls a derived amount of yield from the Olympus treasury each week
///         and uses it, along with the backing of previously purchased OHM, to purchase OHM off the
///         market using a Bond Protocol Fixed-Expiration market.
contract Protocoloop {
    ISDAI public immutable sdai = ISDAI(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
    ERC20 public immutable dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public immutable ohm = IERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
    Auctioneer public immutable auctioneer = Auctioneer(0x007FEA32545a39Ff558a1367BBbC1A22bc7ABEfD);
    Treasury public immutable treasury = Treasury(0xa8687A15D4BE32CC8F0a8a7B9704a4C3993D9613);
    Clearinghouse public immutable clearinghouse =
        Clearinghouse(0xe6343ad0675c9b8d3f32679ae6adba0766a2ab4c);
    Oracle public immutable oracle;

    uint48 public epoch; // a running counter to keep time
    uint256 public nextYield; // the amount of DAI to pull as yield at the start of the next week
    uint256 public lastReserveBalance; // the SDAI reserve balance, in DAI, at the end of the last week
    uint256 public lastConversionRate; // the SDAI conversion rate at the end of the last week
    // we use this to compute yield accrued
    // yield = last reserve balance * ((current conversion rate / last conversion rate) - 1)

    uint48 public constant epochLength = 21; // one week
    uint256 public constant backingPerToken = 114 * 1e8; // assume backing of $11.40
    bool public isShutdown;

    constructor(uint256 initialReserveBalance, uint256 initialConversionRate) {
        epoch = 20;
        lastReserveBalance = initialReserveBalance;
        lastConversionRate = initialConversionRate;
    }

    ///////////////////////// EXTERNAL /////////////////////////

    /// @notice create a new bond market at the end of the day with some portion of remaining funds
    function endEpoch() public onlyHeart {
        if (isShutdown) return; // disabling this contract will not interfere with heartbeat
        epoch++;

        if (epoch % 3 != 0) return; // only execute once per day
        if (epoch == epochLength) {
            // reset at end of week
            epoch = 0;
            withdraw(nextYield);

            nextYield = getNextYield();
            lastConversionRate = sdai.convertToAssets(1e18);
            lastReserveBalance = getReserveBalance();
        }

        getBackingForPurchased(); // convert yesterdays ohm purchases into dai

        // use portion of dai balance based on day of the week
        // i.e. day one, use 1/7th; day two, use 1/6th; 1/5th; 1/4th; ...
        uint256 bidAmount = dai.balanceOf(address(this)) / (7 - (epoch / 3));

        createMarket(bidAmount);
    }

    /// @notice allow manager to increase (by maximum 10%) or decrease yield for week if contract is inaccurate
    /// @param newNextYield to fund
    function adjustNextYield(uint256 newNextYield) external onlyManager {
        if (newNextYield > nextYield && ((newNextYield * 1e18) / nextYield) > (11 * 1e17))
            revert TooDifferent();

        nextYield = newNextYield;
    }

    /// @notice retire contract by burning ohm balance and transferring tokens to treasury
    /// @param tokensToTransfer list of tokens to transfer back to treasury (i.e. DAI)
    function shutdown(ERC20[] memory tokensToTransfer) external onlyManager {
        isShutdown = true;
        ohm.burn(ohm.balanceOf(address(this)));
        for (uint256 i; i < tokensToTransfer.length; i++) {
            ERC20 token = tokensToTransfer[i];
            token.transfer(token.balanceOf(address(this)), address(treasury));
        }
    }

    ///////////////////////// INTERNAL /////////////////////////

    /// @notice create bond protocol market with given budget
    /// @param bidAmount amount of DAI to fund bond market with
    function createMarket(uint256 bidAmount) internal {
        Auctioneer.MarketParams memory params = new Auctioneer.MarketParams(
            dai,
            ohm,
            address(0),
            false,
            bidAmount,
            oracle.currentPrice(),
            rbs.upperCushion(),
            0,
            0,
            block.timestamp + 1 days,
            2 hours,
            0
        );

        auctioneer.createMarket(params);
    }

    /// @notice internal function to burn ohm and retrieve backing
    function getBackingForPurchased() internal {
        uint256 balance = ohm.balanceOf(address(this));
        uint256 backingForBalance = balance * backingPerToken; // balance and backingPerToken are 9 decimals, dai amount is 18 decimals

        ohm.burn(balance);
        withdraw(backingForBalance);
    }

    /// @notice internal function to withdraw DAI from treasury
    /// @dev withdraws SDAI and converts to DAI
    /// @param amount an amount to withdraw, in DAI
    function withdraw(uint256 amount) internal {
        treasury.withdraw(sdai, sdai.convertToShares(amountDAI));
        sdai.redeem(sdai.balanceOf(address(this)), address(this), address(this));
    }

    ///////////////////////// VIEW /////////////////////////

    /// @notice fetch combined sdai balance of clearinghouse and treasury, in DAI
    function getReserveBalance() public view returns (uint256 balance) {
        balance += sdai.balanceOf(address(clearinghouse));
        balance += sdai.balanceOf(address(treasury));
        balance = sdai.convertToAssets(balance);
    }

    /// @notice compute yield for the next week
    function getNextYield() public view returns (uint256 yield) {
        // add sDAI rewards accrued for week
        yield +=
            ((lastReserveBalance * sdai.convertToAssets(1e18)) / lastConversionRate) -
            reserveBalance();
        // add clearinghouse interest accrued for week (0.5% divided by 52 weeks)
        yield += (clearinghouse.principalReceivables() * 5) / 1000 / 52;
    }
}
