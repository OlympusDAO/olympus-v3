// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {MockUniV2Pair} from "src/test/mocks/MockUniV2Pair.sol";

/// @notice A very simple deployment script
contract TestGdaoDeploy is Script {

  /// @notice The main script entrypoint
  /// @return mockuniv2 The deployed contract
  function run() external returns (MockUniV2Pair mockuniv2) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address test_gdao = vm.envAddress("TEST_GDAO");
    address test_dai = vm.envAddress("TEST_DAI");
    mockuniv2 = new MockUniV2Pair(test_gdao, test_dai);

    vm.stopBroadcast();
    return mockuniv2;
  }
}

// constructor(address token0_, address token1_) {