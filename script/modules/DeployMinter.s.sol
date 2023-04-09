// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {GoerliMinter} from "src/modules/MINTR/GoerliMinter.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract DeployMinter is Script {

  /// @notice The main script entrypoint
  /// @return minter The deployed contract
  function run() external returns (GoerliMinter minter) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);

    address gdao = vm.envAddress("SEPOLIA_GDAO_1_1");
    address kernel_addr = vm.envAddress("SEPOLIA_KERNEL");
    Kernel kernel = Kernel(kernel_addr);
    minter = new GoerliMinter(kernel, gdao);

    vm.stopBroadcast();
    return minter;
  }
}