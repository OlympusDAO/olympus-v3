// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {IBondAggregator} from "src/interfaces/IBondAggregator.sol";
import {BondFixedTermSDA} from "src/policies/BondFixedTermSDA.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {IBondTeller} from "src/interfaces/IBondTeller.sol";


/// @notice A very simple deployment script
contract DeployFixedBondSDA is Script {

  /// @notice The main script entrypoint
  /// @return fixed_term_sda The deployed contract
  function run() external returns (BondFixedTermSDA fixed_term_sda) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    
    address teller_addr = vm.envAddress("SEPOLIA_BOND_FIXED_TELLER"); // #3 account in anvil
    IBondTeller teller = IBondTeller(teller_addr);
    address aggregator_addr = vm.envAddress("SEPOLIA_AGGREGATOR");
    address guardian = vm.envAddress("SEPOLIA_GUARDIAN");

    IBondAggregator aggregator = IBondAggregator(aggregator_addr);
    address authority_addr = vm.envAddress("SEPOLIA_AUTHORITY");

    Authority authority = Authority(authority_addr);

    fixed_term_sda = new BondFixedTermSDA(teller, aggregator, guardian, authority);

    vm.stopBroadcast();
    return fixed_term_sda;
  }
}

        // address protocol_,
        // IBondAggregator aggregator_,
        // address guardian_,
        // Authority authority_