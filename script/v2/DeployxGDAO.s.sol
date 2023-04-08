// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {xGDAO} from "src/external/xGDAOERC20.sol";

/// @notice A very simple deployment script
contract xGdaoDeploy is Script {

  /// @notice The main script entrypoint
  /// @return xgdao The deployed contract
  function run() external returns (xGDAO xgdao) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    xgdao = new xGDAO();

    vm.stopBroadcast();
    return xgdao;
  }
}