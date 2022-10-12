// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import "src/Kernel.sol";
import {TreasuryCustodian} from "policies/TreasuryCustodian.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

/// @notice Script to deploy the Treasury Custodian Policy
/// @dev    The address that this script is broadcast from must have write access to the contracts being configured
contract TreasuryCustodianDeploy is Script {
    Kernel public kernel;

    /// Policies
    TreasuryCustodian public treasuryCustodian;
    RolesAdmin public rolesAdmin;

    function deploy(address guardian_) external {
        // Load addresses
        kernel = Kernel(vm.envAddress("KERNEL"));
        rolesAdmin = RolesAdmin(vm.envAddress("ROLESADMIN"));

        vm.startBroadcast();

        // Deploy treasury custodian

        treasuryCustodian = new TreasuryCustodian(kernel);
        console2.log("TreasuryCustodian deployed at:", address(treasuryCustodian));

        /// Execute actions on Kernel
        /// Approve policies
        kernel.executeAction(Actions.ActivatePolicy, address(treasuryCustodian));

        /// Configure access control for policies

        // /// TreasuryCustodian roles
        // rolesAdmin.grantRole("custodian", guardian_);

        vm.stopBroadcast();
    }

    /// @dev must be called with address which has custodian role
    function increaseDebt(address borrower, uint256 amount) external {
        // Load address from environment
        treasuryCustodian = TreasuryCustodian(vm.envAddress("TRSRYCUSTODIAN"));
        ERC20 reserve = ERC20(vm.envAddress("DAI_ADDRESS"));

        // Increase the borrower's debt by amount
        vm.broadcast();
        treasuryCustodian.increaseDebt(reserve, borrower, amount);
    }
}
