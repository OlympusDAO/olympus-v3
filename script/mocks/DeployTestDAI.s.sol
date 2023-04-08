// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {Script} from 'forge-std/Script.sol';
import {DAI} from "src/external/testnet/testDAI.sol";

/// @notice A very simple deployment script
contract DeployDAI is Script {

  /// @notice The main script entrypoint
  /// @return dai The deployed contract
  function run() external returns (DAI dai) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address authority = vm.envAddress("SEPOLIA_AUTHORITY");    // uint256 chainId = 31337;
    
    uint256 sepoliaChainId = vm.envUint("SEPOLIA_CHAIN_ID");
    DAI dai = new DAI(sepoliaChainId);
    vm.stopBroadcast();
    return dai;
  }
}
        // uint256 chainId_