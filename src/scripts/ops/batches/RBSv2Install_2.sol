// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";

import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

import "src/Kernel.sol";
import {OlympusSupply} from "modules/SPPLY/OlympusSupply.sol";
import {BLVaultSupply} from "modules/SPPLY/submodules/BLVaultSupply.sol";
import {BunniSupply} from "modules/SPPLY/submodules/BunniSupply.sol";
import {CustomSupply} from "modules/SPPLY/submodules/CustomSupply.sol";
import {MigrationOffsetSupply} from "modules/SPPLY/submodules/MigrationOffsetSupply.sol";
import {CrossChainBridge} from "policies/CrossChainBridge.sol";

contract RBSv2Install_2 is OlyBatch {
    // Existing Olympus Contracts
    address kernel;
    address crossChainBridge;
    address arbBridge;
    address opBridge;

    // New Contracts
    address spply;
    address blVaultSupply;
    address bunniSupply;
    address customSupply;
    address migrationOffsetSupply;
    address newCrossChainBridge;

    function loadEnv() internal override {
        kernel = envAddress("current", "olympus.Kernel");
        crossChainBridge = envAddress("last", "olympus.policies.CrossChainBridge");

        arbBridge = address(0); // TODO: Change
        opBridge = address(0); // TODO: Change

        spply = envAddress("current", "olympus.modules.OlympusSupply");
        blVaultSupply = envAddress("current", "olympus.submodules.SPPLY.BLVaultSupply");
        bunniSupply = envAddress("current", "olympus.submodules.SPPLY.BunniSupply");
        customSupply = envAddress("current", "olympus.submodules.SPPLY.CustomSupply");
        migrationOffsetSupply = envAddress("current", "olympus.submodules.SPPLY.MigrationOffsetSupply");
        newCrossChainBridge = envAddress("current", "olympus.policies.CrossChainBridge");
    }

    function RBSv2Install_2_1(bool send_) external isDaoBatch(send_) {
        // This DAO MS batch:
        // 1. Installs the OlympusSupply module
        // 2. Installs the BLVaultSupply submodule on the OlympusSupply module
        // 3. Installs the BunniSupply submodule on the OlympusSupply module
        // 4. Installs the MigrationOffsetSupply submodule on the OlympusSupply module
        // 5. Deactivates the old CrossChainBridge policy
        // 6. Activates the new CrossChainBridge policy
        // 7. Set trusted remotes on the new CrossChainBridge policy

        // 1. Install the OlympusSupply module
        addToBatch(kernel, abi.ecnodeWithSelector(Kernel.executeAction.selector, Actions.InstallModule, spply));

        // 2. Install the BLVaultSupply submodule on the OlympusSupply module
        addToBatch(spply, abi.encodeWithSelector(OlympusSupply.installSubmodule.selector, blVaultSupply));

        // 3. Install the BunniSupply submodule on the OlympusSupply module
        addToBatch(spply, abi.encodeWithSelector(OlympusSupply.installSubmodule.selector, bunniSupply));

        // 4. Install the MigrationOffsetSupply submodule on the OlympusSupply module
        addToBatch(spply, abi.encodeWithSelector(OlympusSupply.installSubmodule.selector, migrationOffsetSupply));

        // 5. Deactivate the old CrossChainBridge policy
        addToBatch(kernel, abi.encodeWithSelector(Kernel.executeAction.selector, Actions.DeactivatePolicy, crossChainBridge));

        // 6. Activate the new CrossChainBridge policy
        addToBatch(kernel, abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, newCrossChainBridge));

        // 7. Set trusted remotes on the new CrossChainBridge policy
        addToBatch(newCrossChainBridge, abi.encodeWithSelector(CrossChainBridge.setTrustedRemote.selector, 110, arbBridge));
        addToBatch(newCrossChainBridge, abi.encodeWithSelector(CrossChainBridge.setTrustedRemote.selector, 111, opBridge));
    }
}