// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {GoerliDaoERC20Token} from "src/external/GDAOERC20.sol";

/// @notice A very simple deployment script
contract GdaoDeploy is Script {

  /// @notice The main script entrypoint
  /// @return gdao The deployed contract
  function run() external returns (GoerliDaoERC20Token gdao) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address authority = vm.envAddress("LOCAL_AUTHORITY");
    gdao = new GoerliDaoERC20Token(authority);

    vm.stopBroadcast();
    return gdao;
  }
}