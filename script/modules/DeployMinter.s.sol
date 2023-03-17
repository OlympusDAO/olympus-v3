// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {GdaoMinter} from "src/modules/MINTR/GdaoMinter.sol";
import {Kernel} from "src/Kernel.sol";

/// @notice A very simple deployment script
contract DeployMinter is Script {

  /// @notice The main script entrypoint
  /// @return minter The deployed contract
  function run() external returns (GdaoMinter minter) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address gdao = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    address kernel_addr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    Kernel kernel = Kernel(kernel_addr);
    minter = new GdaoMinter(kernel, gdao);

    vm.stopBroadcast();
    return minter;
  }
}