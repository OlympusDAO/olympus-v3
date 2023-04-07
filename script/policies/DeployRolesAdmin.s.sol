// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract DeployRolesAdmin is Script {

  /// @notice The main script entrypoint
  /// @return roles_admin The deployed contract
  function run() external returns (RolesAdmin roles_admin) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address kernel_addr = vm.envAddress("KERNEL");
    Kernel kernel = Kernel(kernel_addr);

    roles_admin = new RolesAdmin(kernel);

    vm.stopBroadcast();
    return roles_admin;
  }
}

        // Kernel kernel_,