// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {MockPrice} from "src/test/mocks/MockPrice.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract DeployMockPrice is Script {

  /// @notice The main script entrypoint
  /// @return mock_price The deployed contract
  function run() external returns (MockPrice mock_price) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address kernel_addr = vm.envAddress("KERNEL");
    uint48 observationFrequency = 28800; // 3x a day
    uint256 minimumTargetPrice = 10410000000000000000; // 10.41? 

    Kernel kernel = Kernel(kernel_addr);

    mock_price = new MockPrice(kernel, observationFrequency, minimumTargetPrice);

    vm.stopBroadcast();
    return mock_price;
  }
}


        // Kernel kernel_,
        // uint48 observationFrequency_,
        // uint256 minimumTargetPrice_