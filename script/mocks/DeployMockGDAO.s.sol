// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {GDAO} from "src/test/MockGDAO.sol";

/// @notice A very simple deployment script
contract MockGDAODeploy is Script {

  /// @notice The main script entrypoint
  /// @return mgdao The deployed contract
  function run() external returns (GDAO mgdao) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    mgdao = new GDAO();

    vm.stopBroadcast();
    return mgdao;
  }
}