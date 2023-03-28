// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {GoerliDaoPrice} from "src/modules/PRICE/GoerliDaoPrice.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract DeployPrice is Script {

  /// @notice The main script entrypoint
  /// @return price The deployed contract
  function run() external returns (GoerliDaoPrice price) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address kernel_addr = vm.envAddress("KERNEL");
    address gdaoEthPriceFeed_addr = vm.envAddress("MOCK_PRICE"); // address -> oracle? MockPrice contract (deploy first)
    AggregatorV2V3Interface gdaoEthPriceFeed = AggregatorV2V3Interface(gdaoEthPriceFeed_addr);
    uint48 gdaoEthUpdateThreshold = 86400; //1x a day
    address reserveEthPriceFeed_addr = vm.envAddress("MOCK_RESERVE"); // address -> oracle? MockPrice contract (deploy first)
    AggregatorV2V3Interface reserveEthPriceFeed = AggregatorV2V3Interface(reserveEthPriceFeed_addr);
    uint48 reserveEthUpdateThreshold = 86400; //1x a day
    uint48 observationFrequency = 28800; // 3x a day
    uint48 movingAverageDuration = 2592000;
    uint256 minimumTargetPrice = 10410000000000000000; // 10.41?

    Kernel kernel = Kernel(kernel_addr);

    price = new GoerliDaoPrice(kernel, gdaoEthPriceFeed, gdaoEthUpdateThreshold, reserveEthPriceFeed, reserveEthUpdateThreshold, observationFrequency, movingAverageDuration, minimumTargetPrice);

    vm.stopBroadcast();
    return price;
  }
}



        // Kernel kernel_,
        // AggregatorV2V3Interface gdaoEthPriceFeed_,
        // uint48 gdaoEthUpdateThreshold_,
        // AggregatorV2V3Interface reserveEthPriceFeed_,
        // uint48 reserveEthUpdateThreshold_,
        // uint48 observationFrequency_,
        // uint48 movingAverageDuration_,
        // uint256 minimumTargetPrice_