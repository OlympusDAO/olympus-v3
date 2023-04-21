// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {Kernel} from "src/Kernel.sol";
import "src/modules/INSTR/GoerliDaoInstructions.sol";
import "src/modules/MINTR/GoerliMinter.sol";
import "src/modules/PRICE/GoerliDaoPrice.sol";
import "src/modules/RANGE/GoerliDaoRange.sol";
import "src/modules/ROLES/GoerliDaoRoles.sol";
import "src/modules/TRSRY/GoerliDaoTreasury.sol";
import "src/modules/VOTES/GoerliDaoVotes.sol";
// import "src/policies/Governance.v1.sol";
import "src/policies/Distributor.sol";
import "src/policies/Emergency.sol";
import "src/policies/TreasuryCustodian.sol";
import "src/policies/RolesAdmin.sol";

/// @notice A very simple deployment script
contract KernelDeploy is Script {
  GoerliDaoInstructions gdaoInstr;
  GoerliMinter gdaoMinter;
  GoerliDaoPrice gdaoPrice;
  GoerliDaoRange gdaoRange;
  GoerliDaoRoles gdaoRoles;
  GoerliDaoTreasury gdaoTreasury;
  GoerliDaoVotes gdaoVotes;

  Distributor distributor;
  Emergency emergency;
  RolesAdmin roles_admin;
  TreasuryCustodian treasury_custodian;

  
  // address tgd_addr = vm.envAddress("GOERLI_GDAO"); //update env
  ERC20 constant TGD = ERC20(0xba7caC3E2A1391bb9D5edfD64793cCD4Fd29Dc09);

  address staking_addr = vm.envAddress("GOERLI_STAKING"); //update env
  uint256 initialRate = 12055988; // 50M% APR

// authority, gdao, staking, sgdao, xgdao should already be deployed at this point

  /// @notice The main script entrypoint
  /// @return kernel The deployed contract
  function run() external returns (Kernel kernel) {    
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV_5");
    vm.startBroadcast(deployerPrivateKey);
    kernel = new Kernel();
    
    gdaoInstr = new GoerliDaoInstructions(kernel);
    gdaoMinter = new GoerliMinter(kernel, address(TGD));
    // gdaoPrice = new GoerliDaoPrice(kernel, gdaoEthPriceFeed, gdaoEthUpdateThreshold, reserveEthPriceFeed, reserveEthUpdateThreshold, observationFrequency, movingAverageDuration, minimumTargetPrice);
    // gdaoRange = new GoerliDaoRange();
    gdaoRoles = new GoerliDaoRoles(kernel);
    gdaoTreasury = new GoerliDaoTreasury(kernel);
    // gdaoVotes = new GoerliDaoVotes();
    
    distributor = new Distributor(kernel, address(TGD), staking_addr, initialRate);
    emergency = new Emergency(kernel);
    treasury_custodian = new TreasuryCustodian(kernel);
    roles_admin = new RolesAdmin(kernel);


    
    kernel.executeAction(Actions.InstallModule, address(gdaoInstr));
    kernel.executeAction(Actions.InstallModule, address(gdaoMinter));
    kernel.executeAction(Actions.InstallModule, address(gdaoRoles));
    kernel.executeAction(Actions.InstallModule, address(gdaoTreasury));

    kernel.executeAction(Actions.ActivatePolicy, address(distributor));
    kernel.executeAction(Actions.ActivatePolicy, address(emergency));
    kernel.executeAction(Actions.ActivatePolicy, address(roles_admin));
    kernel.executeAction(Actions.ActivatePolicy, address(treasury_custodian));
    
    // operator?
    // emergency
    // roles admin
    // treasury custodian
    // bondcallback?




    vm.stopBroadcast();
    return kernel;
  }
}