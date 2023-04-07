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
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);

    address test_gdai = vm.envAddress("TEST_DAI");
    address test_gdao = vm.envAddress("TEST_GDAO");
    address local_staking = vm.envAddress("LOCAL_STAKING_ADDR");
    address authority = vm.envAddress("LOCAL_AUTHORITY");

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