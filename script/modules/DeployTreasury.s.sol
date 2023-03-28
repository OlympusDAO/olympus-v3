// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {GoerliDaoTreasury} from "src/modules/TRSRY/GoerliDaoTreasury.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract DeployTreasury is Script {

  /// @notice The main script entrypoint
  /// @return treasury The deployed contract
  function run() external returns (GoerliDaoTreasury treasury) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address kernel_addr = vm.envAddress("KERNEL");

    Kernel kernel = Kernel(kernel_addr);

    treasury = new GoerliDaoTreasury(kernel);

    vm.stopBroadcast();
    return treasury;
  }
}

        // Kernel kernel_,
