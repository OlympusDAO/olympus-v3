// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';
import {GDAOStaking} from "src/v2/GDAOStaking.sol";
import {Kernel} from "src/Kernel.sol";


/// @notice A very simple deployment script
contract GDAOStakingDeploy is Script {

  /// @notice The main script entrypoint
  /// @return staking The deployed contract
  function run() external returns (GDAOStaking staking) {
    string memory seedPhrase = vm.readFile(".secret");
    uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    vm.startBroadcast(privateKey);
    address gdao = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512; 
    address sgdao = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512; // update when deployed
    address xgdao = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512; // update when deployed
    uint256 epochLength = 28800;
    uint256 firstEpochNumber = 1;
    uint256 firstEpochTime = 1679376680;
    address authority = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    GDAOStaking staking = new GDAOStaking(gdao, sgdao, xgdao, epochLength, firstEpochNumber, firstEpochTime, authority);

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
