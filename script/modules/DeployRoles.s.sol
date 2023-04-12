// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import {GoerliDaoRoles} from "src/modules/ROLES/GoerliDaoRoles.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract DeployRoles is Script {

  /// @notice The main script entrypoint
  /// @return roles The deployed contract
  function run() external returns (GoerliDaoRoles roles) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address kernel_addr = vm.envAddress("SEPOLIA_KERNEL");

    Kernel kernel = Kernel(kernel_addr);

    roles = new GoerliDaoRoles(kernel);

    vm.stopBroadcast();
    return roles;
  }
}

        // Kernel kernel_,
