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

// SPPLY submodules
import {BLVaultSupply} from "modules/SPPLY/submodules/BLVaultSupply.sol";
import {BunniSupply} from "modules/SPPLY/submodules/BunniSupply.sol";
import {MigrationOffsetSupply} from "modules/SPPLY/submodules/MigrationOffsetSupply.sol";

/// @notice     Activates and configures SPPLY v1
/// @notice     Migrates to CrossChainBridge v1.1
contract RBSv2Install_2_SPPLY is OlyBatch {
    // Existing Olympus Contracts
    address kernel;
    address crossChainBridgeV1;
    address arbBridge;
    address opBridge;
    address blVaultManagerLido;
    address blVaultManagerLusd;

    // New Contracts
    address spply;
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

        arbBridge = envAddressWithChain("arbitrum", "current", "olympus.policies.CrossChainBridge");
        opBridge = envAddressWithChain("optimism", "current", "olympus.policies.CrossChainBridge");

        blVaultManagerLido = envAddress("current", "olympus.policies.BLVaultManagerLido");
        blVaultManagerLusd = envAddress("current", "olympus.policies.BLVaultManagerLusd");

        daoWorkingWallet = envAddress("current", "olympus.legacy.workingWallet");

        spply = envAddress("current", "olympus.modules.OlympusSupply");
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
        // 2. Installs the BLVaultSupply submodule on the OlympusSupply module
        // 3. Installs the BunniSupply submodule on the OlympusSupply module
        // 4. Installs the MigrationOffsetSupply submodule on the OlympusSupply module
        // 5. Installs the BrickedSupply submodule on the OlympusSupply module
        // 6. Deactivates the old CrossChainBridge policy
        // 7. Activates the new CrossChainBridge policy
        // 8. Set trusted remotes on the new CrossChainBridge policy
        // 9. Categorizes protocol-owned-treasury supply
        // 10. Categorizes DAO supply

        // 1. Install the OlympusSupply module
        console2.log("Installing OlympusSupply module");
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.InstallModule, spply)
        );

        // 2. Install the BLVaultSupply submodule on the OlympusSupply module
        console2.log("Installing BLVaultSupply submodule");
        addToBatch(
            spply,
            abi.encodeWithSelector(
                ModuleWithSubmodules.installSubmodule.selector,
                BLVaultSupply(blVaultSupply)
            )
        );

        // 2a. Configure the BLVaultSupply submodule with the existing BLV managers
        console2.log("Adding BLVLidoManager to BLVaultSupply");
        addToBatch(
            blVaultSupply,
            abi.encodeWithSelector(BLVaultSupply.addVaultManager.selector, blVaultManagerLido)
        );
        console2.log("Adding BLVLusdManager to BLVaultSupply");
        addToBatch(
            blVaultSupply,
            abi.encodeWithSelector(BLVaultSupply.addVaultManager.selector, blVaultManagerLusd)
        );

        // 3. Install the BunniSupply submodule on the OlympusSupply module
        // No configuration needed - will be performed by BunniManager
        console2.log("Installing BunniSupply submodule");
        addToBatch(
            spply,
            abi.encodeWithSelector(
                ModuleWithSubmodules.installSubmodule.selector,
                BunniSupply(bunniSupply)
            )
        );

        // 4. Install the MigrationOffsetSupply submodule on the OlympusSupply module
        // No configuration needed - already done at deployment
        console2.log("Installing MigrationOffsetSupply submodule");
        addToBatch(
            spply,
            abi.encodeWithSelector(
                ModuleWithSubmodules.installSubmodule.selector,
                MigrationOffsetSupply(migrationOffsetSupply)
            )
        );

        // 5. Install the BrickedSupply submodule on the OlympusSupply module
        // No configuration needed - already done at deployment
        // TODO enable
        // console2.log("Installing BrickedSupply submodule");
        // addToBatch(
        //     spply,
        //     abi.encodeWithSelector(
        //         ModuleWithSubmodules.installSubmodule.selector,
        //         BrickedSupply(brickedSupply)
        //     )
        // );

        // 6. Deactivate the old CrossChainBridge policy
        console2.log("Deactivating old CrossChainBridge policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                crossChainBridgeV1
            )
        );

        // 7. Activate the new CrossChainBridge policy
        console2.log("Activating new CrossChainBridge policy");
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                crossChainBridgeV1_1
            )
        );

        // 8. Set trusted remotes on the new CrossChainBridge policy
        console2.log("Setting Arbitrum bridge as trusted remote on new CrossChainBridge policy");
        addToBatch(
            crossChainBridgeV1_1,
            abi.encodeWithSelector(CrossChainBridge.setTrustedRemote.selector, 110, arbBridge)
        );
        console2.log("Setting Optimism bridge as trusted remote on new CrossChainBridge policy");
        addToBatch(
            crossChainBridgeV1_1,
            abi.encodeWithSelector(CrossChainBridge.setTrustedRemote.selector, 111, opBridge)
        );

        // 9. Categorize protocol-owned-treasury supply
        console2.log("Categorizing DAO MS as protocol-owned-treasury supply");
        addToBatch(
            spply,
            abi.encodeWithSelector(
                OlympusSupply.categorize.selector,
                daoMS,
                SupplyCategory.wrap("protocol-owned-treasury")
            )
        );

        // 10. Categorize DAO supply
        console2.log("Categorizing DAO working wallet as DAO supply");
        addToBatch(
            spply,
            abi.encodeWithSelector(
                OlympusSupply.categorize.selector,
                daoWorkingWallet,
                SupplyCategory.wrap("dao")
            )
        );
    }
}
