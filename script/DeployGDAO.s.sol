// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {GDAO} from "src/external/GDAO.sol";

/// @notice A very simple deployment script
contract GdaoDeploy is Script {

  /// @notice The main script entrypoint
  /// @return gdao The deployed contract
  function run() external returns (GDAO gdao) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address authority = vm.envAddress("SEPOLIA_AUTHORITY");
    gdao = new GDAO(authority);

    vm.stopBroadcast();
    return gdao;
  }
}