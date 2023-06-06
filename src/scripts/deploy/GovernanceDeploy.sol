// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusVotes} from "modules/VOTES/OlympusVotes.sol";
import {OlympusInstructions} from "modules/INSTR/OlympusInstructions.sol";
import {Parthenon} from "policies/Governance/Parthenon.sol";
import {VohmVault} from "policies/Governance/VohmVault.sol";

/// @notice Script to deploy the Governance System in the Olympus Bophades
contract GovernanceDeploy is Script {
    Kernel public kernel;

    /// Modules
    OlympusVotes public VOTES;
    OlympusInstructions public INSTR;

    /// Policies
    VohmVault public vaultPolicy;
    Parthenon public parthenon;

    /// Construction variables
    MockERC20 public gOHM;

    /// Goerli testnet addresses

    function deploy() external {
        vm.startBroadcast();

        gOHM = new MockERC20("gOHM", "gOHM", 18);

        /// Set addresses for dependencies
        kernel = new Kernel();
        console2.log("Kernel deployed at:", address(kernel));

        VOTES = new OlympusVotes(kernel, gOHM);
        console2.log("VOTES deployed at:", address(VOTES));

        INSTR = new OlympusInstructions(kernel);
        console2.log("INSTR deployed at:", address(INSTR));

        vaultPolicy = new VohmVault(kernel);
        console2.log("Vault Policy deployed at:", address(vaultPolicy));

        parthenon = new Parthenon(kernel);
        console2.log("Parthenon deployed at:", address(parthenon));

        /// Execute actions on Kernel

        /// Install Modules
        kernel.executeAction(Actions.InstallModule, address(VOTES));
        kernel.executeAction(Actions.InstallModule, address(INSTR));

        /// Approve policies
        kernel.executeAction(Actions.ActivatePolicy, address(vaultPolicy));
        kernel.executeAction(Actions.ActivatePolicy, address(parthenon));

        vm.stopBroadcast();
    }
}
