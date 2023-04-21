// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {TGD} from "src/external/testnet/TGD.sol";

/// @notice A very simple deployment script
contract TgdDeploy is Script {

  /// @notice The main script entrypoint
  /// @return tgd The deployed contract
  function run() external returns (TGD tgd) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV_5");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address authority = vm.envAddress("GOERLI_AUTHORITY"); // update env after Authority Deploy
    tgd = new TGD(authority);
    vm.stopBroadcast();
    return tgd;
  }
}
