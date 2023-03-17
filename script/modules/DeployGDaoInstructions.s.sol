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
    Kernel kernel = Kernel(0x5FbDB2315678afecb367f032d93F642f64180aa3);
    gdao_instr = new GoerliDaoInstructions(kernel);

    vm.stopBroadcast();
    return gdao_instr;
  }
}