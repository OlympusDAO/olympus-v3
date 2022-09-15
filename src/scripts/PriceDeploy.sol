// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusPrice} from "modules/PRICE.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

/// @notice Script to deploy an upgraded version of the PRICE module in the Olympus Bophades system
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract OlympusPriceDeploy is Script {
    using TransferHelper for ERC20;

    /// Modules
    OlympusPrice public PRICE;

    /// Construction variables

    /// Mainnet addresses
    // ERC20 public constant ohm =
    //     ERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5); // OHM mainnet address
    // ERC20 public constant reserve =
    //     ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI mainnet address
    // ERC20 public constant rewardToken =
    //     ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH mainnet address

    // IBondSDA public constant bondAuctioneer =
    //     IBondSDA(address(0));
    // IBondAggregator public constant bondAggregator =
    //     IBondAggregator(address(0));

    // AggregatorV2V3Interface public constant ohmEthPriceFeed =
    //     AggregatorV2V3Interface(0x9a72298ae3886221820B1c878d12D872087D3a23); // OHM/ETH chainlink address
    // AggregatorV2V3Interface public constant reserveEthPriceFeed =
    //     AggregatorV2V3Interface(0x773616E4d11A78F511299002da57A0a94577F1f4); // DAI/ETH chainlink address

    /// Goerli testnet addresses

    /// Mock Price Feed addresses
    AggregatorV2V3Interface public constant ohmEthPriceFeed =
        AggregatorV2V3Interface(0x022710a589C9796dce59A0C52cA4E36f0a5e991A); // OHM/ETH chainlink address
    AggregatorV2V3Interface public constant reserveEthPriceFeed =
        AggregatorV2V3Interface(0xdC8E4eD326cFb730a759312B6b1727C6Ef9ca233); // DAI/ETH chainlink address

    /// Kernel
    Kernel public constant kernel = Kernel(0x64665B0429B21274d938Ed345e4520D1f5ABb9e7);

    function deploy() external {
        vm.startBroadcast();

        /// Deploy new PRICE module
        PRICE = new OlympusPrice(
            kernel,
            ohmEthPriceFeed,
            uint48(24 hours),
            reserveEthPriceFeed,
            uint48(24 hours),
            uint48(8 hours),
            uint48(30 days)
        );
        console2.log("Price module deployed at:", address(PRICE));

        /// Execute actions on Kernel
        /// Install modules
        kernel.executeAction(Actions.UpgradeModule, address(PRICE));

        vm.stopBroadcast();
    }
}

contract DependencyDeploy is Script {
    MockPriceFeed public ohmEthPriceFeed;
    MockPriceFeed public reserveEthPriceFeed;

    function deploy() external {
        vm.startBroadcast();

        // Deploy the price feeds
        ohmEthPriceFeed = new MockPriceFeed();
        console2.log("OHM-ETH Price Feed deployed to:", address(ohmEthPriceFeed));
        reserveEthPriceFeed = new MockPriceFeed();
        console2.log("RESERVE-ETH Price Feed deployed to:", address(reserveEthPriceFeed));

        // Set the decimals of the price feeds
        ohmEthPriceFeed.setDecimals(18);
        reserveEthPriceFeed.setDecimals(18);

        vm.stopBroadcast();
    }
}
