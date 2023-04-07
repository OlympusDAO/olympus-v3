// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {Script} from 'forge-std/Script.sol';
import {DAI} from "src/external/testnet/testDAI.sol";

/// @notice A very simple deployment script
contract DeployDAI is Script {

  /// @notice The main script entrypoint
  /// @return dai The deployed contract
  function run() external returns (DAI dai) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    uint256 chainId = 31337;
    DAI dai = new DAI(chainId);
    vm.stopBroadcast();
    return dai;
  }
}
        // uint256 chainId_