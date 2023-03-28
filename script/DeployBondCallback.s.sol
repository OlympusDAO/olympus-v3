// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {BondCallback} from "src/policies/BondCallback.sol";
import {Kernel} from "src/Kernel.sol";
import {GoerliDaoERC20Token} from "src/external/GDAOERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IBondAggregator} from "src/interfaces/IBondAggregator.sol";

/// @notice A very simple deployment script
contract DeployBondCallback is Script {

  /// @notice The main script entrypoint
  /// @return bond_callback The deployed contract
  function run() external returns (BondCallback bond_callback) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address kernel_addr = vm.envAddress("KERNEL");
    Kernel kernel = Kernel(kernel_addr);
    //get from DeployBondAggregator.s.sol;
    address aggregator_addr = vm.envAddress("BOND_AGGREGATOR");

    IBondAggregator aggregator = IBondAggregator(aggregator_addr);
    address gdao_addr = vm.envAddress("GDAO");

    ERC20 gdao = ERC20(gdao_addr);

    bond_callback = new BondCallback(kernel, aggregator, gdao);

    vm.stopBroadcast();
    return bond_callback;
  }
}

        // Kernel kernel_,
        // IBondAggregator aggregator_,
        // ERC20 gdao_