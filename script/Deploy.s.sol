// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract KernelDeploy is Script {

  /// @notice The main script entrypoint
  /// @return kernel The deployed contract
  function run() external returns (Kernel kernel) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    kernel = new Kernel();

    vm.stopBroadcast();
    return kernel;
  }
}