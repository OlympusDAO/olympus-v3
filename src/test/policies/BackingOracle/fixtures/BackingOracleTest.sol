// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ITimelockQueue} from "src/policies/interfaces/utils/ITimelockQueue.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BackingOracle} from "src/policies/BackingOracle.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

// Constants
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

abstract contract BackingOracleTest is Test {
    Kernel internal _kernel;
    OlympusRoles internal _roles;
    RolesAdmin internal _rolesAdmin;
    BackingOracle internal _oracle;
    address internal constant _ADMIN = address(0xAD111);
    address internal constant _CONFIG_OPERATOR = address(0xC0F1C);
    address internal constant _PROPOSER = address(0xBACC);
    address internal constant _EMERGENCY = address(0xE911);
    bytes32 internal constant _BACKING_ADMIN = "backing_admin";

    function setUp() public virtual {
        vm.warp(100 days);
        _kernel = new Kernel();
        _roles = new OlympusRoles(_kernel);
        _rolesAdmin = new RolesAdmin(_kernel);
        _kernel.executeAction(Actions.InstallModule, address(_roles));
        _kernel.executeAction(Actions.ActivatePolicy, address(_rolesAdmin));
        _rolesAdmin.grantRole(ADMIN_ROLE, _ADMIN);
        _rolesAdmin.grantRole(_BACKING_ADMIN, _PROPOSER);
        _rolesAdmin.grantRole(EMERGENCY_ROLE, _EMERGENCY);
        _oracle = new BackingOracle(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(_oracle));
    }

    modifier givenEnabled() {
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(100e18));
        _;
    }

    modifier givenInactive() {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_oracle));
        _;
    }

    modifier givenRecovered() {
        vm.prank(_ADMIN);
        _oracle.enable(abi.encode(100e18));
        vm.prank(_ADMIN);
        _oracle.disable("");
        vm.prank(_PROPOSER);
        _oracle.reEnable();
        _kernel.executeAction(Actions.DeactivatePolicy, address(_oracle));
        _kernel.executeAction(Actions.ActivatePolicy, address(_oracle));
        _;
    }

    function _expectInactive() internal {
        vm.expectRevert(
            abi.encodeWithSignature("BackingOracle_PolicyNotActive(address)", address(_oracle))
        );
    }

    function _expectChange(uint256 value_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBackingOracle.BackingOracle_BackingChangeTooLarge.selector,
                100e18,
                value_,
                90e18,
                110e18
            )
        );
    }
}
