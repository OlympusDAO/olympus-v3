// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import "src/Kernel.sol";
import {BaseLiquidityAMO} from "policies/lending/abstracts/BaseLiquidityAMO.sol";

// Import external dependencies
import {AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";

/// @title Olympus Single-Sided stETH Liquidity AMO
contract StethLiquidityAMO is BaseLiquidityAMO {
    // ========= STATE ========= //

    // Balancer Contracts
    IVault public vault;
    IPool public liquidityPool;

    // Price Feeds
    AggregatorV3Interface public ohmEthPriceFeed; // OHM/ETH price feed
    AggregatorV3Interface public ethUsdPriceFeed; // ETH/USD price feed
    AggregatorV3Interface public stethUsdPriceFeed; // stETH/USD price feed

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel kernel_,
        address ohm_,
        address steth_,
        address vault_,
        address liquidityPool_,
        address ohmEthPriceFeed_,
        address ethUsdPriceFeed_,
        address stethUsdPriceFeed_
    ) BaseLiquidityAMO(kernel_, ohm_, steth_) {
        // Set Balancer contracts
        vault = IVault(vault_);
        liquidityPool = IPool(liquidityPool_);

        // Set price feeds
        ohmEthPriceFeed = AggregatorV3Interface(ohmEthPriceFeed_);
        ethUsdPriceFeed = AggregatorV3Interface(ethUsdPriceFeed_);
        stethUsdPriceFeed = AggregatorV3Interface(stethUsdPriceFeed_);
    }

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    function _valueCollateral(uint256 amount_) internal view override returns (uint256) {
        (, int256 stethPrice_, , , ) = stethUsdPriceFeed.latestRoundData();
        (, int256 ohmPrice_, , , ) = ohmEthPriceFeed.latestRoundData();
        (, int256 ethPrice_, , , ) = ethUsdPriceFeed.latestRoundData();

        uint256 ohmUsd = uint256((ohmPrice_ * ethPrice_) / 1e18);

        return (amount_ * ohmUsd) / (uint256(stethPrice_) * 1e9);
    }

    function _deposit(uint256 ohmAmount_, uint256 pairAmount_) internal override returns (uint256) {
        // OHM-stETH BPT before
        uint256 bptBefore = ERC20(address(liquidityPool)).balanceOf(address(this));

        // Build join pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(pairToken);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = ohmAmount_;
        maxAmountsIn[1] = pairAmount_;

        JoinPoolRequest memory joinPoolRequest = JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(1, maxAmountsIn, 0), // need to change last parameter based on estimate of LP received
            fromInternalBalance: false
        });

        // Join Balancer pool
        ohm.approve(address(vault), ohmAmount_);
        pairToken.approve(address(vault), pairAmount_);
        vault.joinPool(
            IBasePool(liquidityPool).getPoolId(),
            address(this),
            address(this),
            joinPoolRequest
        );
        // OHM-PAIR BPT after
        lpAmountOut = ERC20(address(liquidityPool)).balanceOf(address(this)) - bptBefore;

        return lpAmountOut;
    }

    function _withdraw(uint256 lpAmount_) internal overrider returns (uint256, uint256) {
        // OHM and pair token amounts before
        uint256 ohmBefore = ohm.balanceOf(address(this));
        uint256 pairTokenBefore = pairToken.balanceOf(address(this));

        // Build exit pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(pairToken);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 0; // TODO: find way to calculate without adding function args
        minAmountsOut[1] = 0; // TODO: find way to calculate without adding function args

        ExitPoolRequest memory exitPoolRequest = ExitPoolRequest({
            assets: assets,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(1, lpAmount_),
            toInternalBalance: false
        });

        // Exit Balancer pool
        ERC20(address(liquidityPool)).approve(address(vault), lpAmount_);
        vault.exitPool(
            IBasePool(liquidityPool).getPoolId(),
            address(this),
            payable(address(this)),
            exitPoolRequest
        );
        // OHM and pair token amounts received
        uint256 ohmReceived = ohm.balanceOf(address(this)) - ohmBefore;
        uint256 pairTokenReceived = pairToken.balanceOf(address(this)) - pairTokenBefore;

        return (ohmReceived, pairTokenReceived);
    }
}
