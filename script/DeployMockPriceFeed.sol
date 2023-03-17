// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {MockPriceFeed} from "src/test/mocks/MockPriceFeed.sol";

/// @notice A very simple deployment script
contract DeployMockPriceFeed is Script {

  /// @notice The main script entrypoint
  /// @return mock_price_feed The deployed contract
  function run() external returns (MockPriceFeed mock_price_feed) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);

    mock_price_feed = new MockPriceFeed();

    vm.stopBroadcast();
    return mock_price_feed;
  }
}