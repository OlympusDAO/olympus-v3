// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {console2} from "forge-std/console2.sol";
import {WithEnvironment} from "../WithEnvironment.s.sol";
import {LayerZeroConstants} from "../LayerZeroConstants.sol";

import {Kernel, Actions} from "src/Kernel.sol";

import {OlympusAuthority} from "src/external/OlympusAuthority.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";

import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {CrossChainBridge} from "src/policies/CrossChainBridge.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {Emergency} from "src/policies/Emergency.sol";
import {TreasuryCustodian} from "src/policies/TreasuryCustodian.sol";
import {Minter} from "src/policies/Minter.sol";

/// @notice Script to deploy the Bridge to a separate testnet
contract L2Deploy is WithEnvironment {
    function _getLzEndpoint() internal view returns (address) {
        return _envAddressNotZero("external.layerzero.endpoint");
    }

    function _getDaoMultisig() internal view returns (address) {
        return _envAddressNotZero("olympus.multisig.dao");
    }

    function _getEmergencyMultisig() internal view returns (address) {
        return _envAddressNotZero("olympus.multisig.emergency");
    }

    function _endsWith(string memory str, string memory suffix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory suffixBytes = bytes(suffix);

        if (strBytes.length < suffixBytes.length) return false;

        for (uint256 i = 0; i < suffixBytes.length; i++) {
            if (strBytes[strBytes.length - suffixBytes.length + i] != suffixBytes[i]) return false;
        }

        return true;
    }

    function isTestnet(string calldata chain_) internal pure returns (bool) {
        // If the chain ends with sepolia, it is a testnet
        if (_endsWith(chain_, "sepolia")) {
            return true;
        }

        // If the chain ends with bartio, it is a testnet
        if (_endsWith(chain_, "bartio")) {
            return true;
        }

        return false;
    }

    function grantRoles(string calldata chain_) external {
        _loadEnv(chain_);
        vm.startBroadcast();

        RolesAdmin rolesAdmin = RolesAdmin(_envAddressNotZero("olympus.policies.RolesAdmin"));
        OlympusMinter MINTR = OlympusMinter(_envAddressNotZero("olympus.modules.OlympusMinter"));
        OlympusAuthority auth = OlympusAuthority(
            _envAddressNotZero("olympus.legacy.OlympusAuthority")
        );

        console2.log("");
        console2.log("Granting roles");

        // Assign emergency roles
        {
            console2.log("Granting emergency roles to emergency multisig", _getEmergencyMultisig());
            rolesAdmin.grantRole("emergency_shutdown", _getEmergencyMultisig());
            rolesAdmin.grantRole("emergency_restart", _getEmergencyMultisig());
        }

        // TreasuryCustodian
        {
            console2.log("Granting custodian role to DAO multisig", _getDaoMultisig());
            rolesAdmin.grantRole("custodian", _getDaoMultisig());
        }

        // CrossChainBridge
        // The role is required for setup. It will be transferred to the multisig later
        {
            console2.log("Granting bridge admin role to deployer", msg.sender);
            rolesAdmin.grantRole("bridge_admin", msg.sender);
        }

        // OlympusAuthority
        {
            console2.log("Granting OlympusAuthority vault role to MINTR", address(MINTR));
            auth.pushVault(address(MINTR), true);
            console2.log(
                "Granting OlympusAuthority governor role to DAO multisig",
                _getDaoMultisig()
            );
            auth.pushGovernor(_getDaoMultisig(), true);
        }

        console2.log("Roles granted");

        vm.stopBroadcast();
    }

    /// @notice Deploys a new Bophades installation to a new chain
    /// @dev    Deploys the following contracts:
    ///         - OlympusAuthority
    ///         - OlympusERC20Token (OHM)
    ///         - Kernel
    ///         - OlympusMinter
    ///         - OlympusRoles
    ///         - OlympusTreasury
    ///         - RolesAdmin
    ///         - CrossChainBridge
    ///         - Emergency
    ///         - TreasuryCustodian
    ///         - Minter (testnet only)
    function deploy(string calldata chain_) external {
        _loadEnv(chain_);

        bool isTestnet_ = isTestnet(chain_);

        console2.log("");
        console2.log("Deploying to", chain_);
        console2.log("Is testnet:", isTestnet_);
        console2.log("Initial Kernel executor:", msg.sender);

        vm.startBroadcast();

        // Keep deployer as vault in order to transfer minter role after OHM
        // token is deployed
        OlympusAuthority auth = new OlympusAuthority(
            msg.sender, // governor/owner, will be set to daoMultisig later
            _getDaoMultisig(), // guardian
            _getDaoMultisig(), // policy
            msg.sender // vault, will be set to MINTR later
        );
        OlympusERC20Token ohm = new OlympusERC20Token(address(auth));
        console2.log("OlympusAuthority deployed at:", address(auth));
        console2.log("OlympusERC20Token deployed at:", address(ohm));

        // Set addresses for dependencies
        Kernel kernel = new Kernel();
        console2.log("Kernel deployed at:", address(kernel));

        OlympusMinter MINTR = new OlympusMinter(kernel, address(ohm));
        console2.log("MINTR deployed at:", address(MINTR));

        OlympusRoles ROLES = new OlympusRoles(kernel);
        console2.log("ROLES deployed at:", address(ROLES));

        OlympusTreasury TRSRY = new OlympusTreasury(kernel);
        console2.log("Treasury deployed at:", address(TRSRY));

        CrossChainBridge bridge = new CrossChainBridge(kernel, _getLzEndpoint());
        console2.log("Bridge deployed at:", address(bridge));

        RolesAdmin rolesAdmin = new RolesAdmin(kernel);
        console2.log("RolesAdmin deployed at:", address(rolesAdmin));

        Emergency emergency = new Emergency(kernel);
        console2.log("Emergency deployed at:", address(emergency));

        TreasuryCustodian treasuryCustodian = new TreasuryCustodian(kernel);
        console2.log("TreasuryCustodian deployed at:", address(treasuryCustodian));

        Minter minter;
        if (isTestnet_) {
            minter = new Minter(kernel);
            console2.log("Minter deployed at:", address(minter));
        }

        console2.log("");
        console2.log("Deployments complete");
        console2.log("Please update the src/scripts/env.json file with the new addresses");

        // Execute actions on Kernel

        console2.log("");
        console2.log("Installing modules/policies in Kernel");

        // Install Modules
        kernel.executeAction(Actions.InstallModule, address(MINTR));
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.InstallModule, address(TRSRY));

        // Activate Policies
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(bridge));
        kernel.executeAction(Actions.ActivatePolicy, address(emergency));
        kernel.executeAction(Actions.ActivatePolicy, address(treasuryCustodian));
        if (isTestnet_) {
            kernel.executeAction(Actions.ActivatePolicy, address(minter));
        }
        console2.log("Kernel actions complete");
        vm.stopBroadcast();
    }

    /// @notice Deploys a new CrossChainBridge
    function deployBridge(string calldata chain_) public {
        _loadEnv(chain_);

        address kernel = _envAddressNotZero("olympus.Kernel");
        address lzEndpoint = _envAddressNotZero("external.layerzero.endpoint");

        console2.log("Deploying bridge to", chain_);
        console2.log("Kernel:", kernel);
        console2.log("LZ Endpoint:", lzEndpoint);

        vm.startBroadcast();
        CrossChainBridge bridge = new CrossChainBridge(Kernel(kernel), lzEndpoint);
        vm.stopBroadcast();
        console2.log("Bridge deployed at:", address(bridge));
    }

    /// @notice Installs a deployed CrossChainbridge in the Kernel and grants the "bridge_admin" role to the caller.
    /// @dev    The caller must be the kernel executor
    function installBridge(string calldata chain_) public {
        _loadEnv(chain_);

        address kernel = _envAddressNotZero("olympus.Kernel");
        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");
        address crossChainBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");

        console2.log("Installing bridge in Kernel");
        console2.log("Kernel:", kernel);
        console2.log("RolesAdmin:", rolesAdmin);
        console2.log("CrossChainBridge:", crossChainBridge);

        vm.startBroadcast();
        Kernel(kernel).executeAction(Actions.ActivatePolicy, address(crossChainBridge));
        RolesAdmin(rolesAdmin).grantRole("bridge_admin", msg.sender);
        vm.stopBroadcast();

        console2.log("Bridge installed in Kernel");
    }

    /// @notice Configures a CrossChainBridge to trust messages from another bridge
    /// @dev    The caller must have the "bridge_admin" role
    ///
    ///         This should be run on the CrossChainBridge that will receive messages from the remote bridge
    function setupBridge(string calldata localChain_, string calldata remoteChain_) public {
        _loadEnv(localChain_);

        address localBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");
        address remoteBridge = _envAddressNotZero(
            remoteChain_,
            "olympus.policies.CrossChainBridge"
        );
        uint16 remoteLzChainId = LayerZeroConstants.getRemoteEndpointId(remoteChain_);

        console2.log("Setting up bridge on chain", localChain_);
        console2.log("Remote chain:", remoteChain_);
        console2.log("Local bridge:", localBridge);
        console2.log("Remote bridge:", remoteBridge);
        console2.log("Remote LZ chain ID:", remoteLzChainId);

        vm.startBroadcast();
        CrossChainBridge(localBridge).setTrustedRemoteAddress(
            remoteLzChainId,
            abi.encodePacked(remoteBridge)
        );
        vm.stopBroadcast();

        console2.log("Bridge setup complete");
    }

    /// @notice Grants the "bridge_admin" role to an address
    /// @dev    The caller must be the role admin
    ///         This is unlikely to be needed, as deploy/installBridge will grant the role to the deployer and handOffToMultisig will grant it to the multisig
    function grantBridgeAdminRole(address rolesAdmin_, address to_) public {
        vm.startBroadcast();
        RolesAdmin(rolesAdmin_).grantRole("bridge_admin", to_);
        vm.stopBroadcast();
    }

    /// @notice Completes the handoff of the installation from the deployer to the multisig
    /// @dev    The caller must be the deployer
    function handoffToMultisig(string calldata chain_) public {
        _loadEnv(chain_);

        address daoMultisig = _getDaoMultisig();
        address kernel = _envAddressNotZero("olympus.Kernel");
        address rolesAdmin = _envAddressNotZero("olympus.policies.RolesAdmin");

        console2.log("Starting handoff to DAO multisig", daoMultisig);

        vm.startBroadcast();

        // Remove bridge_admin role from deployer
        console2.log("Removing bridge_admin role from deployer", msg.sender);
        RolesAdmin(rolesAdmin).revokeRole("bridge_admin", msg.sender);

        // Give roles to multisig and pull admin
        console2.log("Granting bridge_admin role to DAO multisig", daoMultisig);
        RolesAdmin(rolesAdmin).grantRole("bridge_admin", daoMultisig);

        // Propose DAO multisig as new admin
        console2.log("Proposing DAO multisig as new admin", daoMultisig);
        RolesAdmin(rolesAdmin).pushNewAdmin(daoMultisig);

        console2.log("Changing executor to multisig", daoMultisig);
        Kernel(kernel).executeAction(Actions.ChangeExecutor, daoMultisig);
        vm.stopBroadcast();

        console2.log("Handoff complete");
        console2.log(
            "DAO multisig will need to call RolesAdmin.pullNewAdmin() to complete the handoff"
        );
    }
}
