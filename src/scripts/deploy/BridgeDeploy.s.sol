// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Kernel, Actions} from "src/Kernel.sol";

import {OlympusAuthority} from "src/external/OlympusAuthority.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";

import {OlympusMinter, MINTRv1} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles, ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {CrossChainBridge} from "src/policies/CrossChainBridge.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

/// @notice Script to deploy the Bridge to a separate testnet
contract BridgeDeploy is Script {
    Kernel public kernel;

    // Modules
    OlympusMinter public MINTR;
    OlympusRoles public ROLES;

    // Policies
    CrossChainBridge public bridge;
    RolesAdmin public rolesAdmin;

    // Construction variables
    OlympusAuthority public auth;
    OlympusERC20Token public ohm;

    // Deploy ohm, authority, kernel, MINTR, ROLES, rolesadmin to new testnet.
    // Assumes that the caller is the executor
    function deploy(address lzEndpoint_, address multisig_) external {
        vm.startBroadcast();

        // Arb goerli endpoint
        //address lzEndpoint = 0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab;

        // Optimism endpoint = 0x3c2269811836af69497E5F486A85D7316753cf62

        // Keep deployer as vault in order to transfer minter role after OHM
        // token is deployed
        auth = new OlympusAuthority(msg.sender, multisig_, multisig_, msg.sender);
        ohm = new OlympusERC20Token(address(auth));
        console2.log("OlympusAuthority deployed at:", address(auth));
        console2.log("OlympusERC20Token deployed at:", address(ohm));

        // Set addresses for dependencies
        kernel = new Kernel();
        console2.log("Kernel deployed at:", address(kernel));

        MINTR = new OlympusMinter(kernel, address(ohm));
        console2.log("MINTR deployed at:", address(MINTR));

        ROLES = new OlympusRoles(kernel);
        console2.log("ROLES deployed at:", address(ROLES));

        bridge = new CrossChainBridge(kernel, lzEndpoint_);
        console2.log("Bridge deployed at:", address(bridge));

        rolesAdmin = new RolesAdmin(kernel);
        console2.log("RolesAdmin deployed at:", address(rolesAdmin));

        // Execute actions on Kernel

        // Install Modules
        kernel.executeAction(Actions.InstallModule, address(MINTR));
        kernel.executeAction(Actions.InstallModule, address(ROLES));

        // Approve policies
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(bridge));

        // Multisig still needs to claim the admin role
        rolesAdmin.grantRole("bridge_admin", msg.sender);
        rolesAdmin.pushNewAdmin(multisig_);

        // Grant roles
        auth.pushVault(address(MINTR), true);
        auth.pushGovernor(multisig_, true);

        vm.stopBroadcast();
    }

    // To allow calling this separately. Assumes sender is executor
    // (ie cant be used where we're using Multisig)
    function installBridge(address kernel_, address rolesAdmin_, address bridge_) public {
        vm.startBroadcast();
        //deployBridge(kernel_, lzEndpoint_);
        Kernel(kernel_).executeAction(Actions.ActivatePolicy, address(bridge_));
        RolesAdmin(rolesAdmin_).grantRole("bridge_admin", msg.sender);
        vm.stopBroadcast();
    }

    function deployBridge(address kernel_, address lzEndpoint_) public {
        vm.broadcast();
        bridge = new CrossChainBridge(Kernel(kernel_), lzEndpoint_);
        console2.log("Bridge deployed at:", address(bridge));
    }

    // Caller must have "bridge_admin" role
    function setupBridge(
        address localBridge_,
        address remoteBridge_,
        uint16 remoteLzChainId_
    ) public {
        // Begin bridge setup
        bytes memory path1 = abi.encodePacked(remoteBridge_, localBridge_);

        vm.broadcast();
        CrossChainBridge(localBridge_).setTrustedRemote(remoteLzChainId_, path1);
    }

    function grantBridgeAdminRole(address rolesAdmin_, address to_) public {
        vm.broadcast();
        RolesAdmin(rolesAdmin_).grantRole("bridge_admin", to_);
    }

    // Change executor, bridge_admin and RolesAdmin admin to multisig
    function handoffToMultisig(address multisig_, address kernel_, address rolesAdmin_) public {
        vm.startBroadcast();

        // Remove bridge_admin role from deployer
        RolesAdmin(rolesAdmin_).revokeRole("bridge_admin", msg.sender);

        // Give roles to multisig and pull admin
        RolesAdmin(rolesAdmin_).grantRole("bridge_admin", multisig_);
        RolesAdmin(rolesAdmin_).pullNewAdmin();
        Kernel(kernel_).executeAction(Actions.ChangeExecutor, multisig_);

        vm.stopBroadcast();
    }
}
