// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test} from "forge-std/Test.sol";

// Contracts
import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZEndpointDelegate} from "src/policies/bridge/LZEndpointDelegate.sol";
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_CONFIGURATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockLZBridgeGateway} from "src/test/policies/bridge/LZEndpointDelegate/MockLZBridgeGateway.sol";

/// @dev Minimal test base for LZEndpointDelegate. The delegate is deployed against a freshly
///      built Kernel + OlympusRoles + RolesAdmin stack and points at a `MockLZBridgeGateway`
///      that mirrors the real gateway's `LZ_ENDPOINT()` view.
contract LZEndpointDelegateTestBase is Test {
    Kernel kernel;
    OlympusRoles roles;
    RolesAdmin rolesAdmin;
    LZEndpointDelegate lzDelegate;
    MockLZBridgeGateway mockGateway;

    address gateway;
    address lzEndpoint = makeAddr("lzEndpoint");

    address admin = makeAddr("admin");
    address bridgeAdmin = makeAddr("bridgeAdmin");
    address bridgeConfigurator = makeAddr("bridgeConfigurator");

    uint32 constant CANONICAL_EID = 1;
    uint32 constant NONCANONICAL_EID = 2;

    function setUp() public virtual {
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        mockGateway = new MockLZBridgeGateway(lzEndpoint);
        gateway = address(mockGateway);
        lzDelegate = new LZEndpointDelegate(kernel, gateway);

        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(lzDelegate));

        rolesAdmin.grantRole(ADMIN_ROLE, admin);
        rolesAdmin.grantRole(BRIDGE_ADMIN_ROLE, bridgeAdmin);
        rolesAdmin.grantRole(BRIDGE_CONFIGURATOR_ROLE, bridgeConfigurator);
    }
}
