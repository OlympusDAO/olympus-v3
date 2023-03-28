// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {Kernel} from "src/Kernel.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {Faucet} from "src/test/mocks/Faucet.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice A very simple deployment script
contract DeployFaucet is Script {

  /// @notice The main script entrypoint
  /// @return success The deployed contract
  function run() external returns (bool success) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);

    address faucet = vm.envAddress("FAUCET");
    //faucet.dripTestAmounts();
    faucet.drip(1);
    faucet.drip(2);
    success = true;

    vm.stopBroadcast();
    return success;
  }
}

        // address admin_,
        // ERC20 ohm_,
        // ERC20 reserve_,
        // uint256 ethDrip_,
        // uint256 ohmDrip_,
        // uint256 reserveDrip_,
        // uint256 dripInterval_