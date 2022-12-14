// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Import system dependencies
import "src/Kernel.sol";
import {BaseLiquidityAMO} from "policies/AMOs/abstracts/BaseLiquidityAMO.sol";

// Import external dependencies
import {AggregatorV3Interface} from "src/interfaces/AggregatorV2V3Interface.sol";

/// @title Olympus Single-Sided Liquidity Vault
contract SSLiquidityVault is BaseLiquidityAMO {
    // ========= STATE ========= //

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
        address stethOhmPool_,
        address ohmEthPriceFeed_,
        address ethUsdPriceFeed_,
        address stethUsdPriceFeed_
    ) BaseLiquidityAMO(kernel_, ohm_, steth_, vault_, stethOhmPool_) {
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
}
