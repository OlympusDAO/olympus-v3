// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import "src/Kernel.sol";
import "src/Submodules.sol";

// Bophades modules
import {OlympusSupply} from "modules/SPPLY/OlympusSupply.sol";
import {SPPLYv1} from "modules/SPPLY/SPPLY.v1.sol";
import {Category as SupplyCategory, toCategory as toSupplyCategory} from "modules/SPPLY/SPPLY.v1.sol";

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

    function disable_crosschainbridge() public {
        // This DAO MS batch:
        // 1. Deactivates the CrossChainBridge policy

        // 1. Deactivate the CrossChainBridge policy
        {
            console2.log("Deactivating CrossChainBridge policy");
            addToBatch(
                kernel,
                abi.encodeWithSelector(
                    Kernel.executeAction.selector,
                    Actions.DeactivatePolicy,
                    crossChainBridgeV1
                )
            );
        }
    }

    /// @notice     This function is separate from the DAO batch, so it can be called externally while testing
    function install() public {
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
        // 10. Activates the new CrossChainBridge policy
        // 11. Set trusted remotes on the new CrossChainBridge policy

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
        {
            console2.log("Installing BunniSupply submodule");
            addToBatch(
                supplyConfig,
                abi.encodeWithSelector(
                    SupplyConfig.installSubmodule.selector,
                    BunniSupply(bunniSupply)
                )
            );

            console2.log("Register BunniSupply for observations");
            addToBatch(
                supplyConfig,
                abi.encodeWithSelector(
                    SupplyConfig.registerForObservations.selector,
                    BunniSupply(bunniSupply).SUBKEYCODE()
                )
            );
        }

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

        // 10. Activate the new CrossChainBridge policy
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

        // 11. Set trusted remotes on the new CrossChainBridge policy
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

        // Do test of supply metrics
        console2.log("Testing supply metrics");
        console2.log(
            "    Total supply",
            OlympusSupply(spply).getMetric(SPPLYv1.Metric.TOTAL_SUPPLY)
        );
        console2.log(
            "    Migration offset",
            MigrationOffsetSupply(migrationOffsetSupply).getProtocolOwnedTreasuryOhm()
        );
        console2.log("    Bricked OHM", BrickedSupply(brickedSupply).getProtocolOwnedTreasuryOhm());
        console2.log(
            "    Minus: protocol-owned-treasury",
            OlympusSupply(spply).getSupplyByCategory(toSupplyCategory("protocol-owned-treasury"))
        );
        console2.log(
            "    Minus: dao",
            OlympusSupply(spply).getSupplyByCategory(toSupplyCategory("dao"))
        );
        console2.log(
            "    Circulating supply",
            OlympusSupply(spply).getMetric(SPPLYv1.Metric.CIRCULATING_SUPPLY)
        );
        console2.log(
            "    Minus: protocol-owned-liquidity",
            OlympusSupply(spply).getSupplyByCategory(toSupplyCategory("protocol-owned-liquidity"))
        );
        console2.log(
            "    Minus: protocol-owned-borrowable",
            OlympusSupply(spply).getSupplyByCategory(toSupplyCategory("protocol-owned-borrowable"))
        );
        console2.log(
            "    Floating supply",
            OlympusSupply(spply).getMetric(SPPLYv1.Metric.FLOATING_SUPPLY)
        );
        console2.log("    BL OHM", BLVaultSupply(blVaultSupply).getCollateralizedOhm());
        console2.log(
            "    Backed supply",
            OlympusSupply(spply).getMetric(SPPLYv1.Metric.BACKED_SUPPLY)
        );
    }

    function RBSv2Install_2_1(bool send_) external isDaoBatch(send_) {
        disable_crosschainbridge();
    }

    function RBSv2Install_2_2(bool send_) external isDaoBatch(send_) {
        install();
    }

    function RBSv2Install_2_TEST(bool send_) external {
        // For testing purposes only
        initTestBatch();
        disable_crosschainbridge();
        install();
    }
}
