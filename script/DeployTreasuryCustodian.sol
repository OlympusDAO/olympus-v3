// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {TreasuryCustodian} from "src/policies/TreasuryCustodian.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract DeployTreasuryCustodian is Script {

  /// @notice The main script entrypoint
  /// @return treasury_custodian The deployed contract
  function run() external returns (TreasuryCustodian treasury_custodian) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address kernel_addr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    Kernel kernel = Kernel(kernel_addr);

    treasury_custodian = new TreasuryCustodian(kernel);

    vm.stopBroadcast();
    return treasury_custodian;
  }
}

        // Kernel kernel_,