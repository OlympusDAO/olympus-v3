// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {GoerliDaoInstructions} from "src/modules/INSTR/GoerliDaoInstructions.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract GDaoInstrDeploy is Script {

  /// @notice The main script entrypoint
  /// @return gdao_instr The deployed contract
  function run() external returns (GoerliDaoInstructions gdao_instr) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address kernel_addr = vm.envAddress("KERNEL");
    Kernel kernel = Kernel(kernel_addr);
    gdao_instr = new GoerliDaoInstructions(kernel);

    vm.stopBroadcast();
    return gdao_instr;
  }
}