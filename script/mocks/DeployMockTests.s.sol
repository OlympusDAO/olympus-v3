// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Kernel} from "src/Kernel.sol";
import {MockPolicy} from "src/test/mocks/KernelTestMocks.sol";

/// @notice A very simple deployment script
contract DeployMockTests is Script {

  /// @notice The main script entrypoint
  /// @return test_mocks The deployed contract
  function run() external returns (MockPolicy test_mocks) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    // address kernel_addr = vm.envAddress("LOCAL_KERNEL");
    address sepolia_kernel = vm.envAddress("SEPOLIA_KERNEL");
    // Kernel kernel = Kernel(sepolia_kernel);
    Kernel kernel = Kernel(sepolia_kernel);

    test_mocks = new MockPolicy(kernel);

    vm.stopBroadcast();
    return test_mocks;
  }
}


    // constructor(Kernel kernel_) Policy(kernel_) {}
