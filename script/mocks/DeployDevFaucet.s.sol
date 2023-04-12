// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Kernel} from "src/Kernel.sol";
import {DAI} from "src/external/testnet/testDAI.sol";
import {Faucet} from "src/external/Faucet.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice A very simple deployment script
contract DeployDevFaucet is Script {

  /// @notice The main script entrypoint
  /// @return faucet The deployed contract
  function run() external returns (Faucet faucet) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address authority = vm.envAddress("SEPOLIA_AUTHORITY");

    // address kernel_addr = vm.envAddress("LOCAL_KERNEL");
    address sepolia_kernel = vm.envAddress("SEPOLIA_KERNEL");
    // Kernel kernel = Kernel(sepolia_kernel);

    // address gdao_addr = vm.envAddress("LOCAL_GDAO");
    address sepolia_gdao = vm.envAddress("SEPOLIA_GDAO_1_2");
    ERC20 gdao = ERC20(sepolia_gdao);

    // address mock_reserve_addr = vm.envAddress("TEST_DAI");
    address sepolia_mock_reserve = vm.envAddress("SEPOLIA_DAI");
    ERC20 mock_reserve = ERC20(sepolia_mock_reserve);

    uint256 ethDrip = 1000000000000000000;
    // uint256 gdaoDrip = 1000000000000000;
    uint256 gdaoDrip = 100000000000000000; //1000 GDAO
    uint256 reserveDrip = 10000000000000000000000000;
    uint256 dripInterval = 360;

    Faucet faucet = new Faucet(
        sepolia_kernel,
        gdao,
        mock_reserve,
        ethDrip,
        gdaoDrip,
        reserveDrip,
        dripInterval
    );
    vm.stopBroadcast();
    return faucet;
  }
}

        // address admin_,
        // ERC20 ohm_,
        // ERC20 reserve_,
        // uint256 ethDrip_,
        // uint256 ohmDrip_,
        // uint256 reserveDrip_,
        // uint256 dripInterval_