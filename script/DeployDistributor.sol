// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Distributor} from "src/policies/Distributor.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract DeployDistributor is Script {

  /// @notice The main script entrypoint
  /// @return distributor The deployed contract
  function run() external returns (Distributor distributor) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address kernel_addr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    Kernel kernel = Kernel(kernel_addr);
    address gdao_addr = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    address staking_addr = 0x6D65b498cb23deAba4f3efb28b9fF90f4Bf4b9e2;
    uint256 initialRate = 12055988;
    

    distributor = new Distributor(kernel, gdao_addr, staking_addr, initialRate);

    //vm.stopBroadcast();
    return distributor;
  }
}
        // Kernel kernel_,
        // address gdao_,
        // address staking_,
        // uint256 initialRate_