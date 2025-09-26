// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

contract OCGPermissions is OlyBatch {
    address public ROLES;
    address public rolesAdmin;
    address public timelock;
    address public governor; // This must be the delegator contract

    function loadEnv() internal override {
        // Load addresses from env
        ROLES = envAddress("current", "olympus.modules.OlympusRoles");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        timelock = envAddress("current", "olympus.governance.Timelock");
        governor = envAddress("current", "olympus.governance.GovernorBravoDelegator");
    }

    function script(bool send_) external isDaoBatch(send_) {
        // This script cleans up dangling roles from old contracts and addresses not used for managing the system anymore.
        // At the end, it pushes the RolesAdmin admin role to the Timelock. This must be pulled by the Timelock during the first proposal.
        // 1. Remove the "callback_whitelist" role from an old operator contract
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("callback_whitelist"),
                address(0x1Ce568DbB34B2631aCDB5B453c3195EA0070EC65)
            )
        );
        console2.log("Revoked callback_whitelist from 0x1Ce568DbB34B2631aCDB5B453c3195EA0070EC65");

        // 2. Remove the "callback_whitelist" role from another old operator contract
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("callback_whitelist"),
                address(0x5F15b91B59AD65D490921016d4134c2301197485)
            )
        );
        console2.log("Revoked callback_whitelist from 0x5F15b91B59AD65D490921016d4134c2301197485");

        // 3. Remove the "callback_whitelist" role from another old operator contract
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("callback_whitelist"),
                address(0xbb47C3FFf4eF85703907d3ffca30de278b85df3f)
            )
        );
        console2.log("Revoked callback_whitelist from 0xbb47C3FFf4eF85703907d3ffca30de278b85df3f");

        // 4. Remove the "callback_whitelist" role from another old operator contract
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("callback_whitelist"),
                address(0x0374c001204eF5e7E4F5362A5A2430CB6c219326)
            )
        );
        console2.log("Revoked callback_whitelist from 0x0374c001204eF5e7E4F5362A5A2430CB6c219326");

        // 5. Remove the "callback_whitelist" role from the Policy MS
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("callback_whitelist"),
                address(policyMS)
            )
        );
        console2.log("Revoked callback_whitelist from Policy MS");

        // 6. Remove the "operator_operate" role from an old Heart contract
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("operator_operate"),
                address(0x9C6220fE829d6FC889cde9b4966D2033C4EfFD48)
            )
        );
        console2.log("Revoked operator_operate from 0x9C6220fE829d6FC889cde9b4966D2033C4EfFD48");

        // 7. Remove the "operator_operate" role from another old Heart contract
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("operator_operate"),
                address(0xE05646971Ec444f8449d1CA6Fc8D9793986017d5)
            )
        );
        console2.log("Revoked operator_operate from 0xE05646971Ec444f8449d1CA6Fc8D9793986017d5");

        // 8. Remove the "operator_operate" role from another old Heart contract
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("operator_operate"),
                address(0xeaf46BD21dd9b263F28EEd7260a269fFba9ace6E)
            )
        );
        console2.log("Revoked operator_operate from 0xeaf46BD21dd9b263F28EEd7260a269fFba9ace6E");

        // 9. Remove the "operator_reporter" role from an old BondCallback contract
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("operator_reporter"),
                address(0xbf2B6E99B0E8D4c96b946c182132f5752eAa55C6)
            )
        );
        console2.log("Revoked operator_reporter from 0xbf2B6E99B0E8D4c96b946c182132f5752eAa55C6");

        // 10. Remove the "distributor_admin" role from the Policy MS
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("distributor_admin"),
                address(policyMS)
            )
        );
        console2.log("Revoked distributor_admin from Policy MS");

        // 11. Remove "liquidityvault_admin" roles from DAO MS and Timelock since it's not used anymore
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("liquidityvault_admin"),
                daoMS
            )
        );
        console2.log("Revoked liquidityvault_admin from DAO MS");

        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                bytes32("liquidityvault_admin"),
                timelock
            )
        );
        console2.log("Revoked liquidityvault_admin from Timelock");

        // 12. Push the admin role on the RolesAdmin contract to the Timelock
        addToBatch(rolesAdmin, abi.encodeWithSelector(RolesAdmin.pushNewAdmin.selector, timelock));
        console2.log("Pushed RolesAdmin admin to Timelock");
    }
}
