// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {Timelock} from "src/external/governance/Timelock.sol";

contract OCGActivation is OlyBatch {
    address ROLES;
    address rolesAdmin;
    address timelock;
    address governor; // This must be the delegator contract

    function loadEnv() internal override {
        // Load addresses from env
        ROLES = envAddress("current", "olympus.modules.OlympusRoles");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        timelock = envAddress("current", "olympus.governance.Timelock");
        governor = envAddress("current", "olympus.governance.GovernorBravoDelegator");
    }

    function OCG_Activation(bool send_) external isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. Make sure only DAO MS has "operator_policy"
        // 2. Make sure only DAO MS has "bondmanager_admin"
        // 3. Grant "cooler_overseer" to Timelock
        // 4. Grant "liquidityvault_admin" to Timelock
        // 5. Grant "emergency_admin" to Timelock
        // 6. Grant "emergency_shutdown" role to Timelock
        // 7. Sets first admin on Timelock to Governor

        // 1. Make sure only DAO MS has operator_policy
        //  - Remove from Policy MS
        //  - Grant to DAO MS
        bool policyIsOperator = ROLESv1(ROLES).hasRole(policyMS, "operator_policy");
        bool daoIsOperator = ROLESv1(ROLES).hasRole(daoMS, "operator_policy");
        if (policyIsOperator) {
            addToBatch(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.revokeRole.selector,
                    bytes32("operator_policy"),
                    policyMS
                )
            );
        }
        if (!daoIsOperator) {
            addToBatch(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("operator_policy"),
                    daoMS
                )
            );
        }
        console2.log("operator_policy removed from Policy MS and granted to DAO MS");

        // 2. Make sure only DAO MS has bondmanager_admin
        //  - Remove from Policy MS
        //  - Grant to DAO MS
        bool policyIsBondAdmin = ROLESv1(ROLES).hasRole(policyMS, "bondmanager_admin");
        bool daoIsBondAdmin = ROLESv1(ROLES).hasRole(daoMS, "bondmanager_admin");
        if (policyIsBondAdmin) {
            addToBatch(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.revokeRole.selector,
                    bytes32("bondmanager_admin"),
                    policyMS
                )
            );
        }
        if (!daoIsBondAdmin) {
            addToBatch(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    bytes32("bondmanager_admin"),
                    daoMS
                )
            );
        }
        console2.log("bondmanager_admin removed from Policy MS and granted to DAO MS");

        // 3. Grant "cooler_overseer" to Timelock
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("cooler_overseer"),
                timelock
            )
        );
        console2.log("cooler_overseer granted to Timelock");

        // 4. Grant "liquidityvault_admin" to Timelock
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("liquidityvault_admin"),
                timelock
            )
        );
        console2.log("liquidityvault_admin granted to Timelock");

        // 5. Grant "emergency_admin" to Timelock
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("emergency_admin"),
                timelock
            )
        );
        console2.log("emergency_admin granted to Timelock");

        // 6. Grant "emergency_shutdown" role to Timelock
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("emergency_shutdown"),
                timelock
            )
        );
        console2.log("emergency_shutdown granted to Timelock");

        // 7. Sets first admin on Timelock to Governor
        addToBatch(timelock, abi.encodeWithSelector(Timelock.setFirstAdmin.selector, governor));
        console2.log("Timelock admin set to Governor");
    }
}
