// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import "src/Kernel.sol";

// Bophades policies
import {YieldRepurchaseFacility} from "policies/YieldRepurchaseFacility.sol";
import {OlympusHeart} from "policies/Heart.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

/// @notice     Installs the YieldRepo contract and the new Heart which calls it
contract YieldRepoInstall is OlyBatch {
    address kernel;
    address rolesAdmin;
    address newHeart;
    address yieldRepo;
    address oldHeart;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        rolesAdmin = envAddress("current", "olympus.policies.RolesAdmin");
        newHeart = envAddress("current", "olympus.policies.OlympusHeart");
        yieldRepo = envAddress("current", "olympus.policies.YieldRepurchaseFacility");
        oldHeart = envAddress("last", "olympus.policies.OlympusHeart");
    }

    // Entry point for the batch #1
    function script1_install(bool send_) external isDaoBatch(send_) {
        // Yield Repo Install Script

        // 0. Deactivate the old heart
        addToBatch(oldHeart, abi.encodeWithSelector(OlympusHeart.deactivate.selector));

        // A. Kernel Actions
        // A.1. Uninstall the old heart from the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldHeart
            )
        );

        // A.2. Install the yield repo policy on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, yieldRepo)
        );

        // A.3. Install the new heart policy on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, newHeart)
        );

        // B. Assign Roles
        // B.1. Grant "heart" role to the new heart
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("heart"), newHeart)
        );

        // B.2. Grant "operator_operate" role to the new heart
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                bytes32("operator_operate"),
                newHeart
            )
        );

        // B.3. Grant "loop_daddy" role to the DAO MS
        addToBatch(
            rolesAdmin,
            abi.encodeWithSelector(RolesAdmin.grantRole.selector, bytes32("loop_daddy"), daoMS)
        );
    }

    // Entry point batch #2
    function script2_initialize(bool send_) external isDaoBatch(send_) {
        // Yield Repo Initialize Script
        uint256 initialYieldEarningReserves = 0; // TODO
        uint256 initialConversionRate = 0; // TODO, get from SDAI contract?
        uint256 initialYield = 0; // TODO

        // 1. Initialize the yield repo
        addToBatch(
            yieldRepo,
            abi.encodeWithSelector(
                YieldRepurchaseFacility.initialize.selector,
                initialYieldEarningReserves,
                initialConversionRate,
                initialYield
            )
        );
    }
}
