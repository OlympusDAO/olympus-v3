// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {MockUniV2Pair} from "src/test/mocks/MockUniV2Pair.sol";

/// @notice A very simple deployment script
contract DeployMockUni is Script {

  /// @notice The main script entrypoint
  /// @return mockuniv2 The deployed contract
  function run() external returns (MockUniV2Pair mockuniv2) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);

    address test_gdao = vm.envAddress("SEPOLIA_GDAO");
    address test_dai = vm.envAddress("SEPOLIA_DAI");
    mockuniv2 = new MockUniV2Pair(test_gdao, test_dai);

    vm.stopBroadcast();
    return mockuniv2;
  }
}

// constructor(address token0_, address token1_) {