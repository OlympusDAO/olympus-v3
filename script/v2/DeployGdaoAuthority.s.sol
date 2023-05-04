// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {GdaoAuthority} from "src/external/GdaoAuthority.sol";

/// @notice A very simple deployment script
contract AuthorityDeploy is Script {
  /// @notice The main script entrypoint
  /// @return authority The deployed contract
  function run() external returns (GdaoAuthority authority) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV_5");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address governor = vm.envAddress("GOERLI_DEPLOYER");
    address guardian = vm.envAddress("GOERLI_DEPLOYER");
    address policy = vm.envAddress("GOERLI_MULTISIG");
    address vault = vm.envAddress("GOERLI_DEPLOYER");
    address newVault = vm.envAddress("GOERLI_DEPLOYER");
    authority = new GdaoAuthority(governor, guardian, policy, vault);
    authority.pushVault(newVault, true);

    vm.stopBroadcast();
    return authority;
  }
}

        // address _governor,
        // address _guardian,
        // address _policy,
        // address _vault