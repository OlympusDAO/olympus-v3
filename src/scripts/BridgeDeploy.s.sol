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

    // Deploy to new testnet
    function deploy(address lzEndpoint_, bool isMainnet_) external {
        vm.startBroadcast();

        // Arb goerli endpoint
        //address lzEndpoint = 0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab;

        auth = new OlympusAuthority(msg.sender, msg.sender, msg.sender, msg.sender);
        ohm = new OlympusERC20Token(address(auth));

        // Set addresses for dependencies
        kernel = new Kernel();
        console2.log("Kernel deployed at:", address(kernel));

        MINTR = new OlympusMinter(kernel, address(ohm));
        console2.log("MINTR deployed at:", address(MINTR));

        ROLES = new OlympusRoles(kernel);
        console2.log("ROLES deployed at:", address(ROLES));

        //bridge = new CrossChainBridge(kernel, lzEndpoint_);
        //console2.log("Bridge deployed at:", address(bridge));

        rolesAdmin = new RolesAdmin(kernel);
        console2.log("RolesAdmin deployed at:", address(rolesAdmin));

        // Execute actions on Kernel

        // Install Modules
        kernel.executeAction(Actions.InstallModule, address(MINTR));
        kernel.executeAction(Actions.InstallModule, address(ROLES));

        // Approve policies
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        _deployBridge(address(kernel), lzEndpoint_, isMainnet_); // Deploy and activate bridge

        // Grant roles
        auth.pushVault(address(MINTR), true);
        rolesAdmin.grantRole("bridge_admin", msg.sender);

        vm.stopBroadcast();
    }

    // To allow calling this separately
    function deployBridge(address kernel_, address lzEndpoint_, bool enableCounter_) public {
        vm.broadcast();
        _deployBridge(kernel_, lzEndpoint_, enableCounter_);
    }

    function _deployBridge(address kernel_, address lzEndpoint_, bool enableCounter_) public {
        bridge = new CrossChainBridge(Kernel(kernel_), lzEndpoint_, enableCounter_);
        console2.log("Bridge deployed at:", address(bridge));

        kernel.executeAction(Actions.ActivatePolicy, address(bridge));
    }

    // Caller must have "bridge_admin" role
    function setupBridge(address localBridge_, address remoteBridge_, uint16 remoteChainId_) public {
        vm.startBroadcast();

        rolesAdmin.grantRole("bridge_admin", msg.sender);

        // Begin bridge setup
        bridge.becomeOwner();
        bytes memory path1 = abi.encodePacked(remoteBridge_, localBridge_);
        bridge.setTrustedRemote(remoteChainId_, path1);

        vm.stopBroadcast();
    }

    function grantBridgeAdminRole(address rolesAdmin_, address to_) public {
        vm.broadcast();
        RolesAdmin(rolesAdmin).grantRole("bridge_admin", to_);
    }

}