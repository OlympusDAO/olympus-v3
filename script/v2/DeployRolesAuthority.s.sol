// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Authority} from "solmate/auth/Auth.sol";
import {RolesAuthority} from "src/v2/RolesAuthority.sol";

/// @notice A very simple deployment script
contract DeployRolesAuthority is Script {

  /// @notice The main script entrypoint
  /// @return roles_auth The deployed contract
  function run() external returns (RolesAuthority roles_auth) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    
    address owner = vm.envAddress("SEPOLIA_MULTISIG1"); // owner_
    address authority_addr = vm.envAddress("SEPOLIA_NULL");

    Authority authority = Authority(authority_addr);

    roles_auth = new RolesAuthority(owner, authority);

    vm.stopBroadcast();
    return roles_auth;
  }
}

        // address protocol_,
        // IBondAggregator aggregator_,
        // address guardian_,
        // Authority authority_