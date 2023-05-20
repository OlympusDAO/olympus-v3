// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {GoerliStaking} from "src/v2/GDAOStaking.sol";
import {Kernel} from "src/Kernel.sol";
import {xGDAO} from "src/external/xGDAO.sol";
import {sGDAO} from "src/v2/sGDAO.sol";
import {GdaoAuthority} from "src/external/GdaoAuthority.sol";
import {Distributor} from "src/policies/Distributor.sol";


/// @notice A very simple deployment script
contract GDAOStakingConfigPt2 is Script {

  function run() external {
    // string memory seedPhrase = vm.readFile(".secret");
    // uint256 privateKey = vm.deriveKey(seedPhrase, 0);
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV_5");
    // vm.startBroadcast(privateKey);
    vm.startBroadcast(deployerPrivateKey);
    address gdao = vm.envAddress("GOERLI_GDAO"); // make sure updated in .env
    address sgdao = vm.envAddress("GOERLI_SGDAO"); // make sure updated in .env
    address xgdao = vm.envAddress("GOERLI_XGDAO"); // make sure updated in .env
    address stakingA = vm.envAddress("GOERLI_STAKING"); // make sure updated in .env
    address distributor = vm.envAddress("GOERLI_DISTRIBUTOR"); // make sure updated in .env

    address authority = vm.envAddress("GOERLI_AUTHORITY"); // make sure updated in .env
    GoerliStaking staking = GoerliStaking(stakingA);
    xGDAO xGdao = xGDAO(xgdao);

    // sGDAO(gdao).approve(stakingA, 10000000000);

    // Distributor dist = Distributor(distributor);

    // staking.stake(vm.envAddress("STAKING_TEST"), 1000000, false, true);
    
    Distributor(distributor).triggerRebase();
    // staking.unstake(0x525D98F9B0F4b011cC01720aE1d31d240729D6Ba, 500, false, false);

    vm.stopBroadcast();
    //return staking;
  }
}

        // address _gdao,
        // address _sGDAO,
        // address _xGDAO,
        // uint256 _epochLength,
        // uint256 _firstEpochNumber,
        // uint256 _firstEpochTime,
        // address _authority