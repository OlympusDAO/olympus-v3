// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Kernel} from "src/Kernel.sol";
import {DevFaucet} from "src/external/testnet/DevFaucet.sol";

/// @notice A very simple deployment script
contract DeployFaucet is Script {

  /// @notice The main script entrypoint
  /// @return faucet The deployed contract
  function run() external returns (DevFaucet faucet) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);

    address test_gdai = vm.envAddress("SEPOLIA_DAI");
    address test_gdao = vm.envAddress("SEPOLIA_GDAO_1_2");
    address local_staking = vm.envAddress("SEPOLIA_STAKING_1_1");
    address authority = vm.envAddress("SEPOLIA_AUTHORITY");

    DevFaucet faucet = new DevFaucet(
        test_gdai,
        test_gdao,
        local_staking,
        authority
    );
    vm.stopBroadcast();
    return faucet;
  }
}
        // address dai_,
        // address gdaoV2_,
        // address stakingV2_,
        // address authority_