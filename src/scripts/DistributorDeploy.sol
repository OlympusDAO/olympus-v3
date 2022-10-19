// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import "src/Kernel.sol";
import {Distributor} from "policies/Distributor.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

/// @notice Script to deploy the Distributor Policy
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract DistributorDeploy is Script {
    Kernel public kernel;

    /// Policies
    Distributor public distributor;
    RolesAdmin public rolesAdmin;

    /// External contracts
    address public ohm;
    address public staking;

    function deploy(address policy_) external {
        // Load addresses
        kernel = Kernel(vm.envAddress("KERNEL"));
        rolesAdmin = RolesAdmin(vm.envAddress("ROLESADMIN"));
        staking = vm.envAddress("STAKING_ADDRESS");
        ohm = vm.envAddress("OHM_ADDRESS");

        vm.startBroadcast();

        // Deploy treasury custodian

        distributor = new Distributor(kernel, ohm, staking, vm.envUint("REWARD_RATE"));
        console2.log("Distributor deployed at:", address(distributor));

        /// Execute actions on Kernel
        /// Approve policies
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));

        /// Configure access control for policies

        /// Distributor roles
        rolesAdmin.grantRole("distributor_admin", policy_);

        vm.stopBroadcast();
    }
}
