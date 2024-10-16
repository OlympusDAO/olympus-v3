// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {RGSTYv1} from "src/modules/RGSTY/RGSTY.v1.sol";
import {OlympusContractRegistry} from "src/modules/RGSTY/OlympusContractRegistry.sol";
import {ContractRegistryAdmin} from "src/policies/ContractRegistryAdmin.sol";

contract ContractRegistryAdminTest is Test {
    Kernel public kernel;
    OlympusContractRegistry public RGSTY;
    ContractRegistryAdmin public rgstyAdmin;
    OlympusRoles public ROLES;
    RolesAdmin public rolesAdmin;

    address public admin = address(0x1);
    address public notAdmin = address(0x2);
    address public ohm = address(0x3);

    bytes32 public RGSTY_ROLE = "contract_registry_admin";

    function setUp() public {
        kernel = new Kernel();

        // Install the ROLES module
        ROLES = new OlympusRoles(kernel);
        kernel.executeAction(Actions.InstallModule, address(ROLES));

        // Install the RolesAdmin policy
        rolesAdmin = new RolesAdmin(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Install the RGSTY module
        RGSTY = new OlympusContractRegistry(address(kernel));
        kernel.executeAction(Actions.InstallModule, address(RGSTY));

        // Set up the ContractRegistryAdmin policy
        rgstyAdmin = new ContractRegistryAdmin(address(kernel));
    }

    modifier givenPolicyIsActivated() {
        kernel.executeAction(Actions.ActivatePolicy, address(rgstyAdmin));
        _;
    }

    modifier givenAdminHasRole() {
        rolesAdmin.grantRole(RGSTY_ROLE, admin);
        _;
    }

    modifier givenContractIsRegistered() {
        vm.prank(admin);
        rgstyAdmin.registerContract("ohm", ohm);
        _;
    }

    // ===== TESTS ===== //

    // registerContract
    // when the policy is not active
    //  [X] it reverts
    // when the caller does not have the role
    //  [X] it reverts
    // [X] it registers the contract

    function test_registerContract_policyNotActive_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ContractRegistryAdmin.OnlyPolicyActive.selector));

        rgstyAdmin.registerContract("ohm", ohm);
    }

    function test_registerContract_callerDoesNotHaveRole_reverts()
        public
        givenPolicyIsActivated
        givenAdminHasRole
    {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, RGSTY_ROLE));

        vm.prank(notAdmin);
        rgstyAdmin.registerContract("ohm", ohm);
    }

    function test_registerContract()
        public
        givenPolicyIsActivated
        givenAdminHasRole
        givenContractIsRegistered
    {
        assertEq(RGSTY.getContract("ohm"), ohm, "contract address");
    }

    // updateContract
    // when the policy is not active
    //  [X] it reverts
    // when the caller does not have the role
    //  [X] it reverts
    // [X] it updates the contract

    function test_updateContract_policyNotActive_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ContractRegistryAdmin.OnlyPolicyActive.selector));

        rgstyAdmin.updateContract("ohm", ohm);
    }

    function test_updateContract_callerDoesNotHaveRole_reverts()
        public
        givenPolicyIsActivated
        givenAdminHasRole
    {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, RGSTY_ROLE));

        vm.prank(notAdmin);
        rgstyAdmin.updateContract("ohm", ohm);
    }

    function test_updateContract()
        public
        givenPolicyIsActivated
        givenAdminHasRole
        givenContractIsRegistered
    {
        // Update the contract
        vm.prank(admin);
        rgstyAdmin.updateContract("ohm", address(0x4));

        // Assert values
        assertEq(RGSTY.getContract("ohm"), address(0x4), "contract address");
    }

    // deregisterContract
    // when the policy is not active
    //  [X] it reverts
    // when the caller does not have the role
    //  [X] it reverts
    // [X] it deregisters the contract

    function test_deregisterContract_policyNotActive_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ContractRegistryAdmin.OnlyPolicyActive.selector));

        rgstyAdmin.deregisterContract("ohm");
    }

    function test_deregisterContract_callerDoesNotHaveRole_reverts()
        public
        givenPolicyIsActivated
        givenAdminHasRole
        givenContractIsRegistered
    {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, RGSTY_ROLE));

        vm.prank(notAdmin);
        rgstyAdmin.deregisterContract("ohm");
    }

    function test_deregisterContract()
        public
        givenPolicyIsActivated
        givenAdminHasRole
        givenContractIsRegistered
    {
        // Deregister the contract
        vm.prank(admin);
        rgstyAdmin.deregisterContract("ohm");

        // Assert values
        vm.expectRevert(RGSTYv1.Params_ContractNotRegistered.selector);
        RGSTY.getContract("ohm");
    }
}
