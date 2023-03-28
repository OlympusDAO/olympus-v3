// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {MockOhm} from "src/test/mocks/MockOhm.sol";

/// @notice A very simple deployment script
contract DeployMockReserve is Script {

  /// @notice The main script entrypoint
  /// @return mock_reserve The deployed contract
  function run() external returns (MockOhm mock_reserve) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    string memory name = "Mock Reserve OHM";
    string memory symbol = "mOHM";
    uint8 decimals = 18;
    MockOhm mock_reserve = new MockOhm(
      name,
      symbol, decimals
    );
    vm.stopBroadcast();
    return mock_reserve;
  }
}

        // string memory _name,
        // string memory _symbol,
        // uint8 _decimals
