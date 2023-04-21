// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from 'forge-std/Script.sol';

import {Kernel} from "src/Kernel.sol";
// import "src/policies/Governance.v1.sol";
import "src/policies/Distributor.sol";
import "src/policies/Emergency.sol";
import "src/policies/TreasuryCustodian.sol";
import "src/policies/RolesAdmin.sol";

/// @notice A very simple deployment script
contract RolesDeploy is Script {

  Distributor distributor;
  Emergency emergency;
  RolesAdmin rolesAdmin;
  TreasuryCustodian treasury_custodian;

  address emergency_ms = vm.envAddress("GOERLI_POLICY");
  address guardian = vm.envAddress("GOERLI_KERNEL_5");
  

// authority, gdao, staking, sgdao, xgdao should already be deployed at this point

  /// @notice The main script entrypoint
  /// @return kernel The deployed contract
  function run() external returns (Kernel kernel) {    
    uint256 deployerPrivateKey = vm.envUint("KERNEL_PRIV_5");
    vm.startBroadcast(deployerPrivateKey);
    address kernel_addr = vm.envAddress("GOERLI_KERNEL_5"); // update env after Authority Deploy
    kernel = Kernel(kernel_addr);
    
    address dist_addr = vm.envAddress("GOERLI_DISTRIBUTOR"); // update env after Authority Deploy
    distributor = Distributor(dist_addr);
    
    address emergency_addr = vm.envAddress("GOERLI_EMERGENCY"); // update env after Authority Deploy
    emergency = Emergency(emergency_addr);

    address treasury_c_addr = vm.envAddress("GOERLI_TREASURY_C"); // update env after Authority Deploy
    treasury_custodian = TreasuryCustodian(treasury_c_addr);

    address roles_admin_addr = vm.envAddress("GOERLI_ROLES_ADMIN"); // update env after Authority Deploy
    rolesAdmin = RolesAdmin(roles_admin_addr);
    
    rolesAdmin.grantRole("distributor_admin", address(0x20982640f1133fa091e8848B99cC630571371260));

    rolesAdmin.grantRole("emergency_shutdown", emergency_ms);
    rolesAdmin.grantRole("emergency_restart", guardian);

    rolesAdmin.grantRole("custodian", guardian);


    
    // operator?
    // emergency
    // roles admin
    // treasury custodian
    // bondcallback?




    vm.stopBroadcast();
    return kernel;
  }
}