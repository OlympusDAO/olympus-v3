// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Kernel} from "src/Kernel.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {Faucet} from "src/test/mocks/Faucet.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice A very simple deployment script
contract DeployDevFaucet is Script {

  /// @notice The main script entrypoint
  /// @return faucet The deployed contract
  function run() external returns (Faucet faucet) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address kernel_addr = vm.envAddress("KERNEL");
    Kernel kernel = Kernel(kernel_addr);

    address gdao_addr = vm.envAddress("GDAO");
    ERC20 gdao = ERC20(gdao_addr);
    address mock_reserve_addr = vm.envAddress("MOCK_RESERVE");
    MockOhm mock_reserve = MockOhm(mock_reserve_addr);

    uint256 ethDrip = 1000000000000000000;
    uint256 gdaoDrip = 1000000000000000;
    uint256 reserveDrip = 10000000000000000000000000;
    uint256 dripInterval = 360;

    Faucet faucet = new Faucet(
        kernel_addr,
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