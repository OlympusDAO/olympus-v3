// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Parthenon} from "src/policies/Parthenon.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract DeployParthenon is Script {

  /// @notice The main script entrypoint
  /// @return parthenon The deployed contract
  function run() external returns (Parthenon parthenon) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address kernel_addr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    Kernel kernel = Kernel(kernel_addr);

    parthenon = new Parthenon(kernel);

    vm.stopBroadcast();
    return parthenon;
  }
}
        // Kernel kernel_,
