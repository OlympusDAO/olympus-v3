// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Forwarder} from "src/external/Forwarder.sol";

/// @notice A very simple deployment script
contract ForwarderDeploy is Script {

  /// @notice The main script entrypoint
  /// @return forwarder The deployed contract
  function run() external returns (Forwarder forwarder) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV_5"); // this should be a multisig (executor)
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address depositCoin = vm.envAddress("GOERLI_ETH"); // GETH
    address saleToken = vm.envAddress("GOERLI_GDAO"); // GDAO
    address multisig = vm.envAddress("GOERLI_MULTISIG"); // make sure updated in .env
    forwarder = new Forwarder(depositCoin, saleToken, multisig);
    vm.stopBroadcast();
    return forwarder;
  }
}


    // constructor (address _depositCoin, address _saleToken, address _multisig) {
