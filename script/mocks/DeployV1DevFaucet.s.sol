// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Kernel} from "src/Kernel.sol";
import {DAI} from "src/external/testnet/testDAI.sol";
import {Faucet_V1} from "src/external/V1Faucet.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice A very simple deployment script
contract DeployFaucetV1 is Script {

  /// @notice The main script entrypoint
  /// @return faucet The deployed contract
  function run() external returns (Faucet_V1 faucet) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);

    address sepolia_gdao = vm.envAddress("SEPOLIA_GDAO_1_1");
    address dai_ = vm.envAddress("SEPOLIA_DAI");
    address stakingV2_ = vm.envAddress("SEPOLIA_G_STAKING");
    address authority = vm.envAddress("SEPOLIA_AUTHORITY");

    faucet = new Faucet_V1(
        dai_,
        sepolia_gdao,
        stakingV2_,
        authority
    );

    vm.stopBroadcast();
    return faucet;
  }
}

        // address dai_,
        // address gdao,
        // address stakingV2_,
        // address authority_