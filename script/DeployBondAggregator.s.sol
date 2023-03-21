// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {BondAggregator} from "src/policies/BondAggregator.sol";
import {Kernel} from "src/Kernel.sol";
import {GoerliDaoERC20Token} from "src/external/GDAOERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";


/// @notice A very simple deployment script
contract DeployBondAggregator is Script {

  /// @notice The main script entrypoint
  /// @return bond_aggregator The deployed contract
  function run() external returns (BondAggregator bond_aggregator) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address guardian = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // use test wallet #2
    address authority = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    Authority auth = Authority(authority);
    bond_aggregator = new BondAggregator(guardian, auth);

    vm.stopBroadcast();
    return bond_aggregator;
  }
}

 //    constructor(address guardian_, Authority authority_) Auth(guardian_, authority_) {}
