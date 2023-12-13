// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import "src/Kernel.sol";
import "src/Submodules.sol";

// Bophades modules
import {OlympusSupply} from "modules/SPPLY/OlympusSupply.sol";
import {Category as SupplyCategory} from "modules/SPPLY/SPPLY.v1.sol";

// Bophades policies
import {CrossChainBridge} from "policies/CrossChainBridge.sol";
import {SupplyConfig} from "policies/OCA/SupplyConfig.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

// SPPLY submodules
import {BLVaultSupply} from "modules/SPPLY/submodules/BLVaultSupply.sol";
import {BunniSupply} from "modules/SPPLY/submodules/BunniSupply.sol";
import {MigrationOffsetSupply} from "modules/SPPLY/submodules/MigrationOffsetSupply.sol";
import {BrickedSupply} from "modules/SPPLY/submodules/BrickedSupply.sol";

/// @notice     Activates and configures SPPLY v1
/// @notice     Migrates to CrossChainBridge v1.1
contract RBSv2Install_2_SPPLY is OlyBatch {
    // Existing Olympus Contracts
    address kernel;
    address crossChainBridgeV1;
    address rolesAdmin;
    address arbBridge;
    address opBridge;
    address blVaultManagerLido;
    address blVaultManagerLusd;

    // New Contracts
    address spply;
    address supplyConfig;
    address blVaultSupply;
    address bunniSupply;
    address migrationOffsetSupply;
    address brickedSupply;
    address crossChainBridgeV1_1;

    // Wallets
    address daoWorkingWallet;

    function loadEnv() internal override {
        kernel = envAddress("current", "olympus.Kernel");
        crossChainBridgeV1 = envAddress("current", "olympus.policies.CrossChainBridgeV1");
        crossChainBridgeV1_1 = envAddress("current", "olympus.policies.CrossChainBridgeV1_1");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");

        arbBridge = envAddressWithChain("arbitrum", "current", "olympus.policies.CrossChainBridge");
        opBridge = envAddressWithChain("optimism", "current", "olympus.policies.CrossChainBridge");

        blVaultManagerLido = envAddress("current", "olympus.policies.BLVaultManagerLido");
        blVaultManagerLusd = envAddress("current", "olympus.policies.BLVaultManagerLusd");

        daoWorkingWallet = envAddress("current", "olympus.legacy.workingWallet");

        spply = envAddress("current", "olympus.modules.OlympusSupply");
        supplyConfig = envAddress("current", "olympus.policies.SupplyConfig");
        blVaultSupply = envAddress("current", "olympus.submodules.SPPLY.BLVaultSupply");
        bunniSupply = envAddress("current", "olympus.submodules.SPPLY.BunniSupply");
        migrationOffsetSupply = envAddress(
            "current",
            "olympus.submodules.SPPLY.MigrationOffsetSupply"
        );
        brickedSupply = envAddress("current", "olympus.submodules.SPPLY.BrickedSupply");
    }

    function RBSv2Install_2_1(bool send_) external isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. Installs the OlympusSupply module
        // 2. Installs the SupplyConfig policy
        // 3. Set roles for policy access control
        // 4. Installs the BLVaultSupply submodule on the OlympusSupply module
        // 5. Installs the BunniSupply submodule on the OlympusSupply module
        // 6. Installs the MigrationOffsetSupply submodule on the OlympusSupply module
        // 7. Installs the BrickedSupply submodule on the OlympusSupply module
        // 8. Categorizes protocol-owned-treasury supply
        // 9. Categorizes DAO supply
        // 10. Deactivates the old CrossChainBridge policy
        // 11. Activates the new CrossChainBridge policy
        // 12. Set trusted remotes on the new CrossChainBridge policy

        // 1. Install the OlympusSupply module
        console2.log("Installing OlympusSupply module");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.InstallModule, spply)
        );

        // 2. Install the SupplyConfig policy
        console2.log("Installing SupplyConfig policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                supplyConfig
            )
        );

        // 3. Set roles for policy access control
        //  - Give DAO MS the supplyconfig_admin role
        //  - Give policy MS and DAO MS the supplyconfig_policy role
        console2.log("Granting admin role for SupplyConfig policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("supplyconfig_admin"),
                daoMS
            )
        );
        console2.log("Granting policy role for SupplyConfig policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("supplyconfig_policy"),
                daoMS
            )
        );
        console2.log("Granting policy role for SupplyConfig policy");
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("supplyconfig_policy"),
                policyMS
            )
        );

        // 4. Install the BLVaultSupply submodule on the OlympusSupply module
        //  - The Lido and LUSD BLVaultManagers were already added as managers at deployment-time
        console2.log("Installing BLVaultSupply submodule");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(
                SupplyConfig.installSubmodule.selector,
                BLVaultSupply(blVaultSupply)
            )
        );

        // 5. Install the BunniSupply submodule on the OlympusSupply module
        // No configuration needed - will be performed by BunniManager
        console2.log("Installing BunniSupply submodule");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(SupplyConfig.installSubmodule.selector, BunniSupply(bunniSupply))
        );

        // 6. Install the MigrationOffsetSupply submodule on the OlympusSupply module
        // No configuration needed - already done at deployment
        console2.log("Installing MigrationOffsetSupply submodule");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(
                SupplyConfig.installSubmodule.selector,
                MigrationOffsetSupply(migrationOffsetSupply)
            )
        );

        // 7. Install the BrickedSupply submodule on the OlympusSupply module
        // No configuration needed - already done at deployment
        console2.log("Installing BrickedSupply submodule");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(
                SupplyConfig.installSubmodule.selector,
                BrickedSupply(brickedSupply)
            )
        );

        // 8. Categorize protocol-owned-treasury supply
        console2.log("Categorizing DAO MS as protocol-owned-treasury supply");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(
                SupplyConfig.categorizeSupply.selector,
                daoMS,
                SupplyCategory.wrap("protocol-owned-treasury")
            )
        );

        // 9. Categorize DAO supply
        console2.log("Categorizing DAO working wallet as DAO supply");
        addToBatch(
            supplyConfig,
            abi.encodeWithSelector(
                SupplyConfig.categorizeSupply.selector,
                daoWorkingWallet,
                SupplyCategory.wrap("dao")
            )
        );

        // 10. Deactivate the old CrossChainBridge policy
        console2.log("Deactivating old CrossChainBridge policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                crossChainBridgeV1
            )
        );

        // 11. Activate the new CrossChainBridge policy
        //  - No need to set the admin role, as it was already set when the first version of the policy was installed
        console2.log("Activating new CrossChainBridge policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                crossChainBridgeV1_1
            )
        );

        // 12. Set trusted remotes on the new CrossChainBridge policy
        console2.log("Setting Arbitrum bridge as trusted remote on new CrossChainBridge policy");
        addToBatch(
            crossChainBridgeV1_1,
            abi.encodeWithSelector(
                CrossChainBridge.setTrustedRemoteAddress.selector,
                110,
                abi.encode(arbBridge)
            )
        );
        console2.log("Setting Optimism bridge as trusted remote on new CrossChainBridge policy");
        addToBatch(
            crossChainBridgeV1_1,
            abi.encodeWithSelector(
                CrossChainBridge.setTrustedRemoteAddress.selector,
                111,
                abi.encode(opBridge)
            )
        );
    }
}
