// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {sGDAO} from "src/v2/sGDAO.sol";

/// @notice A very simple deployment script
contract sGdaoDeploy is Script {

  /// @notice The main script entrypoint
  /// @return sgdao The deployed contract
  function run() external returns (sGDAO sgdao) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    sgdao = new sGDAO();

    vm.stopBroadcast();
    return sgdao;
  }
}