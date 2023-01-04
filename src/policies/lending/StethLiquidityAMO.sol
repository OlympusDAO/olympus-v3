// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import "src/Kernel.sol";
import {BaseLiquidityAMO} from "policies/lending/abstracts/BaseLiquidityAMO.sol";

// Import external dependencies
import {AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";
import {JoinPoolRequest, ExitPoolRequest, IVault} from "src/interfaces/IBalancerVault.sol";
import {IBasePool} from "src/interfaces/IBasePool.sol";

/// @title Olympus Single-Sided stETH Liquidity AMO
contract StethLiquidityAMO is BaseLiquidityAMO {
    // ========= STATE ========= //

    // Balancer Contracts
    IVault public vault;

    // Price Feeds
    AggregatorV3Interface public ohmEthPriceFeed; // OHM/ETH price feed
    AggregatorV3Interface public ethUsdPriceFeed; // ETH/USD price feed
    AggregatorV3Interface public stethUsdPriceFeed; // stETH/USD price feed

    // Price Feed Update Thresholds
    uint48 public ohmEthPriceFeedUpdateThreshold;
    uint48 public ethUsdPriceFeedUpdateThreshold;
    uint48 public stethUsdPriceFeedUpdateThreshold;

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
        address stethUsdPriceFeed_,
        uint48 ohmEthPriceFeedUpdateThreshold_,
        uint48 ethUsdPriceFeedUpdateThreshold_,
        uint48 stethUsdPriceFeedUpdateThreshold_
    ) BaseLiquidityAMO(kernel_, ohm_, steth_, liquidityPool_) {
        // Set Balancer vault
        vault = IVault(vault_);

        // Set price feeds
        ohmEthPriceFeed = AggregatorV3Interface(ohmEthPriceFeed_);
        ethUsdPriceFeed = AggregatorV3Interface(ethUsdPriceFeed_);
        stethUsdPriceFeed = AggregatorV3Interface(stethUsdPriceFeed_);

        // Set price feed update thresholds
        ohmEthPriceFeedUpdateThreshold = ohmEthPriceFeedUpdateThreshold_;
        ethUsdPriceFeedUpdateThreshold = ethUsdPriceFeedUpdateThreshold_;
        stethUsdPriceFeedUpdateThreshold = stethUsdPriceFeedUpdateThreshold_;
    }

    //============================================================================================//
    //                                      ADMIN FUNCTIONS                                       //
    //============================================================================================//

    function changeUpdateThresholds(
        uint48 ohmEthPriceFeedUpdateThreshold_,
        uint48 ethUsdPriceFeedUpdateThreshold_,
        uint48 stethUsdPriceFeedUpdateThreshold_
    ) external onlyRole("liquidityamo_admin") {
        ohmEthPriceFeedUpdateThreshold = ohmEthPriceFeedUpdateThreshold_;
        ethUsdPriceFeedUpdateThreshold = ethUsdPriceFeedUpdateThreshold_;
        stethUsdPriceFeedUpdateThreshold = stethUsdPriceFeedUpdateThreshold_;
    }

    //============================================================================================//
    //                                     INTERNAL FUNCTIONS                                     //
    //============================================================================================//

    function _valueCollateral(uint256 amount_) internal view override returns (uint256) {
        uint256 ohmPrice = _validatePrice(
            address(ohmEthPriceFeed),
            uint256(ohmEthPriceFeedUpdateThreshold)
        );
        uint256 ethPrice = _validatePrice(
            address(ethUsdPriceFeed),
            uint256(ethUsdPriceFeedUpdateThreshold)
        );
        uint256 stethPrice = _validatePrice(
            address(stethUsdPriceFeed),
            uint256(stethUsdPriceFeedUpdateThreshold)
        );

        uint256 ohmUsd = uint256((ohmPrice * ethPrice) / 1e18);

        return (amount_ * ohmUsd) / (uint256(stethPrice) * 1e9);
    }

    function _getPoolPrice() internal view override returns (uint256) {
        (, uint256[] memory balances_, ) = vault.getPoolTokens(
            IBasePool(liquidityPool).getPoolId()
        );

        return (balances_[0] * 1e18) / balances_[1];
    }

    function _getPoolOhmShare() internal view override returns (uint256) {
        // Cast pool address from abstract to Balancer Base Pool
        IBasePool pool = IBasePool(liquidityPool);

        (, uint256[] memory balances_, ) = vault.getPoolTokens(pool.getPoolId());
        uint256 bptBalance = pool.balanceOf(address(this));
        uint256 bptTotalSupply = pool.totalSupply();

        if (bptBalance == 0) return 0;
        else return (balances_[0] * bptBalance) / bptTotalSupply;
    }

    function _deposit(
        uint256 ohmAmount_,
        uint256 pairAmount_,
        uint256 minLpAmount_
    ) internal override returns (uint256) {
        // Cast pool address from abstract to Balancer Base Pool
        IBasePool pool = IBasePool(liquidityPool);

        // OHM-stETH BPT before
        uint256 bptBefore = pool.balanceOf(address(this));

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
            userData: abi.encode(1, maxAmountsIn, minLpAmount_),
            fromInternalBalance: false
        });

        // Join Balancer pool
        ohm.approve(address(vault), ohmAmount_);
        pairToken.approve(address(vault), pairAmount_);
        vault.joinPool(pool.getPoolId(), address(this), address(this), joinPoolRequest);

        // OHM-PAIR BPT after
        uint256 lpAmountOut = pool.balanceOf(address(this)) - bptBefore;

        return lpAmountOut;
    }

    function _withdraw(uint256 lpAmount_, uint256[] calldata minTokenAmounts_)
        internal
        override
        returns (uint256, uint256)
    {
        // Cast pool adress from abstract to Balancer Base Pool
        IBasePool pool = IBasePool(liquidityPool);

        // OHM and pair token amounts before
        uint256 ohmBefore = ohm.balanceOf(address(this));
        uint256 pairTokenBefore = pairToken.balanceOf(address(this));

        // Build exit pool request
        address[] memory assets = new address[](2);
        assets[0] = address(ohm);
        assets[1] = address(pairToken);

        ExitPoolRequest memory exitPoolRequest = ExitPoolRequest({
            assets: assets,
            minAmountsOut: minTokenAmounts_,
            userData: abi.encode(1, lpAmount_),
            toInternalBalance: false
        });

        // Exit Balancer pool
        pool.approve(address(vault), lpAmount_);
        vault.exitPool(pool.getPoolId(), address(this), payable(address(this)), exitPoolRequest);

        // OHM and pair token amounts received
        uint256 ohmReceived = ohm.balanceOf(address(this)) - ohmBefore;
        uint256 pairTokenReceived = pairToken.balanceOf(address(this)) - pairTokenBefore;

        return (ohmReceived, pairTokenReceived);
    }
}
