// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {BondFixedTermTeller} from "src/v2/BondFixedTermTeller.sol";
import {IBondAggregator} from "src/interfaces/IBondAggregator.sol";
import {Authority} from "solmate/auth/Auth.sol";

/// @notice A very simple deployment script
contract DeployBondFixedTermTeller is Script {

  /// @notice The main script entrypoint
  /// @return fixed_term_teller The deployed contract
  function run() external returns (BondFixedTermTeller fixed_term_teller) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    
    address protocol = vm.envAddress("SEPOLIA_PROTOCOL"); // #3 account in anvil
    address aggregator_addr = vm.envAddress("SEPOLIA_AGGREGATOR");
    address guardian = vm.envAddress("SEPOLIA_GUARDIAN");

    IBondAggregator aggregator = IBondAggregator(aggregator_addr);
    address authority_addr = vm.envAddress("SEPOLIA_ROLES_AUTH");

    Authority authority = Authority(authority_addr);

    fixed_term_teller = new BondFixedTermTeller(protocol, aggregator, guardian, authority);

    vm.stopBroadcast();
    return fixed_term_teller;
  }
}

        // address protocol_,
        // IBondAggregator aggregator_,
        // address guardian_,
        // Authority authority_