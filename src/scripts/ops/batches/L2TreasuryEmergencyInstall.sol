// SPDX-License-Identifier: AGPL-3.0-or-later
// solhint-disable custom-errors
pragma solidity 0.8.15;

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import {Kernel, Actions} from "src/Kernel.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

/// @notice     Installs missing modules and policies on an existing L2 installation
contract L2TreasuryEmergencyInstall is OlyBatch {
    address public kernel;
    address public rolesAdmin;
    address public trsry;
    address public emergency;
    address public treasuryCustodian;
    address public daoMultisig;
    address public emergencyMultisig;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        trsry = envAddress("current", "olympus.modules.OlympusTreasury");
        emergency = envAddress("current", "olympus.policies.Emergency");
        treasuryCustodian = envAddress("current", "olympus.policies.TreasuryCustodian");
        daoMultisig = envAddress("current", "olympus.multisig.dao");
        emergencyMultisig = envAddress("current", "olympus.multisig.emergency");
    }

    function install(bool send_) external isDaoBatch(send_) {
        // A. Kernel Actions
        // A.1. Install the TRSRY module on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.InstallModule, trsry)
        );

        // A.2. Install the emergency policy on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, emergency)
        );

        // A.3. Install the treasury custodian policy on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                treasuryCustodian
            )
        );

        // B. RolesAdmin Actions
        // B.1. Assign the custodian role to the DAO multisig
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("custodian"), daoMultisig)
        );

        // B.2. Assign the emergency role to the EMERGENCY multisig
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("emergency"),
                emergencyMultisig
            )
        );
    }
}
