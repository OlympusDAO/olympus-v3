// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {GoerliDaoPriceConfig} from "src/policies/PriceConfig.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract DeployPriceConfig is Script {

  /// @notice The main script entrypoint
  /// @return price_config The deployed contract
  function run() external returns (GoerliDaoPriceConfig price_config) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address kernel_addr = vm.envAddress("KERNEL");
    Kernel kernel = Kernel(kernel_addr);
    price_config = new GoerliDaoPriceConfig(kernel);

    vm.stopBroadcast();
    return price_config;
  }
}
        // Kernel kernel_,
