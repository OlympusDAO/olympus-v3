// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {GoerliStaking} from "src/v2/GDAOStaking.sol";
import {Kernel} from "src/Kernel.sol";


/// @notice A very simple deployment script
contract GDAOStakingDeploy is Script {

  /// @notice The main script entrypoint
  /// @return staking The deployed contract
  function run() external returns (GoerliStaking staking) {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV_5");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address gdao = vm.envAddress("GOERLI_GDAO"); // make sure updated in .env
    address sgdao = vm.envAddress("GOERLI_SGDAO"); // make sure updated in .env
    address xgdao = vm.envAddress("GOERLI_XGDAO"); // make sure updated in .env
    uint256 epochLength = 28800;
    uint256 firstEpochNumber = 1;
    uint256 firstEpochTime = 1681078368;
    address authority = vm.envAddress("GOERLI_AUTHORITY"); // make sure updated in .env
    GoerliStaking staking = new GoerliStaking(gdao, sgdao, xgdao, epochLength, firstEpochNumber, firstEpochTime, authority);

    vm.stopBroadcast();
    return staking;
  }
}

        // address _gdao,
        // address _sGDAO,
        // address _xGDAO,
        // uint256 _epochLength,
        // uint256 _firstEpochNumber,
        // uint256 _firstEpochTime,
        // address _authority
