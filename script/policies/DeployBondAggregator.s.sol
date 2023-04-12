// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {BondAggregator} from "src/policies/BondAggregator.sol";
import {Kernel} from "src/Kernel.sol";
import {GDAO} from "src/external/GDAO.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";


/// @notice A very simple deployment script
contract DeployBondAggregator is Script {

  /// @notice The main script entrypoint
  /// @return bond_aggregator The deployed contract
  function run() external returns (BondAggregator bond_aggregator) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address guardian = vm.envAddress("SEPOLIA_GUARDIAN"); // use test wallet #2
    address authority = vm.envAddress("SEPOLIA_AUTHORITY");

    Authority auth = Authority(authority);
    bond_aggregator = new BondAggregator(guardian, auth);

    vm.stopBroadcast();
    return bond_aggregator;
  }
}

 //    constructor(address guardian_, Authority authority_) Auth(guardian_, authority_) {}
