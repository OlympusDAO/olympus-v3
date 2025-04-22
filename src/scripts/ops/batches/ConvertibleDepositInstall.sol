// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {OlyBatch} from "src/scripts/ops/OlyBatch.sol";

// Bophades
import {Kernel, Actions} from "src/Kernel.sol";

/// @notice     Installs the ConvertibleDeposit contracts
contract ConvertibleDepositInstall is OlyBatch {
    address public kernel;
    address public cdepo;
    address public cdpos;
    address public cdAuctioneer;
    address public cdFacility;
    address public emissionManager;
    address public heart;
    address public oldHeart;
    address public oldEmissionManager;

    function loadEnv() internal override {
        // Load contract addresses from the environment file
        kernel = envAddress("current", "olympus.Kernel");
        cdepo = envAddress("current", "olympus.modules.OlympusConvertibleDepository");
        cdpos = envAddress("current", "olympus.modules.OlympusConvertibleDepositPositionManager");
        cdAuctioneer = envAddress("current", "olympus.policies.ConvertibleDepositAuctioneer");
        cdFacility = envAddress("current", "olympus.policies.ConvertibleDepositFacility");
        emissionManager = envAddress("current", "olympus.policies.EmissionManager");
        heart = envAddress("current", "olympus.policies.OlympusHeart");
        oldHeart = envAddress("last", "olympus.policies.OlympusHeart");
        oldEmissionManager = envAddress("last", "olympus.policies.EmissionManager");
    }

    // Entry point for the batch #1
    function script1_install(bool send_) external isDaoBatch(send_) {
        // LoanConsolidator Install Script

        // Validate addresses
        // solhint-disable custom-errors
        require(cdepo != address(0), "CDEPO address is not set");
        require(cdpos != address(0), "CDPOS address is not set");
        require(cdAuctioneer != address(0), "CDAuctioneer address is not set");
        require(cdFacility != address(0), "CDFacility address is not set");
        require(emissionManager != address(0), "EmissionManager address is not set");
        require(heart != address(0), "Heart address is not set");
        // solhint-enable custom-errors

        // A. Kernel Actions
        // A.1. Install the CDEPO module on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.InstallModule, cdepo)
        );

        // A.2. Install the CDPOS module on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.InstallModule, cdpos)
        );

        // A.3. Install the CDAuctioneer policy on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                cdAuctioneer
            )
        );

        // A.4. Install the CDFacility policy on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                cdFacility
            )
        );

        // A.5. Install the EmissionManager policy on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                emissionManager
            )
        );

        // A.6. Install the Heart policy on the kernel
        addToBatch(
            kernel,
            abi.encodeWithSelector(Kernel.executeAction.selector, Actions.ActivatePolicy, heart)
        );

        // Deactivate the old Heart policy
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldHeart
            )
        );

        // Deactivate the old EmissionManager policy
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldEmissionManager
            )
        );

        console2.log("Batch completed");
    }
}
