// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {TestGDAO} from "src/external/testnet/TestGDAO.sol";

/// @notice A very simple deployment script
contract TestGdaoDeploy is Script {

  /// @notice The main script entrypoint
  /// @return testgdao The deployed contract
  function run() external returns (TestGDAO testgdao) {
    
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address authority = vm.envAddress("SEPOLIA_AUTHORITY");
    testgdao = new TestGDAO(authority);

    vm.stopBroadcast();
    return testgdao;
  }
}