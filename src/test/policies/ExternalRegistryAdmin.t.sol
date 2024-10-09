// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {EXREGv1} from "src/modules/EXREG/EXREG.v1.sol";
import {OlympusExternalRegistry} from "src/modules/EXREG/OlympusExternalRegistry.sol";
import {ExternalRegistryAdmin} from "src/policies/ExternalRegistryAdmin.sol";

contract ExternalRegistryAdminTest is Test {
    Kernel public kernel;
    OlympusExternalRegistry public EXREG;
    ExternalRegistryAdmin public exRegAdmin;
    OlympusRoles public ROLES;
    RolesAdmin public rolesAdmin;

    address public admin = address(0x1);
    address public notAdmin = address(0x2);
    address public ohm = address(0x3);

    bytes32 public EXREG_ROLE = "external_registry_admin";

    function setUp() public {
        kernel = new Kernel();

        // Install the ROLES module
        ROLES = new OlympusRoles(kernel);
        kernel.executeAction(Actions.InstallModule, address(ROLES));

        // Install the RolesAdmin policy
        rolesAdmin = new RolesAdmin(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // Install the EXREG module
        EXREG = new OlympusExternalRegistry(address(kernel));
        kernel.executeAction(Actions.InstallModule, address(EXREG));

        // Set up the ExternalRegistryAdmin policy
        exRegAdmin = new ExternalRegistryAdmin(address(kernel));
    }

    modifier givenPolicyIsActivated() {
        kernel.executeAction(Actions.ActivatePolicy, address(exRegAdmin));
        _;
    }

    modifier givenAdminHasRole() {
        rolesAdmin.grantRole(EXREG_ROLE, admin);
        _;
    }

    modifier givenContractIsRegistered() {
        vm.prank(admin);
        exRegAdmin.registerContract("ohm", ohm);
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
        vm.expectRevert(abi.encodeWithSelector(ExternalRegistryAdmin.OnlyPolicyActive.selector));

        exRegAdmin.registerContract("ohm", ohm);
    }

    function test_registerContract_callerDoesNotHaveRole_reverts()
        public
        givenPolicyIsActivated
        givenAdminHasRole
    {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EXREG_ROLE));

        vm.prank(notAdmin);
        exRegAdmin.registerContract("ohm", ohm);
    }

    function test_registerContract()
        public
        givenPolicyIsActivated
        givenAdminHasRole
        givenContractIsRegistered
    {
        assertEq(EXREG.getContract("ohm"), ohm, "contract address");
    }

    // deregisterContract
    // when the policy is not active
    //  [X] it reverts
    // when the caller does not have the role
    //  [X] it reverts
    // [X] it deregisters the contract

    function test_deregisterContract_policyNotActive_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ExternalRegistryAdmin.OnlyPolicyActive.selector));

        exRegAdmin.deregisterContract("ohm");
    }

    function test_deregisterContract_callerDoesNotHaveRole_reverts()
        public
        givenPolicyIsActivated
        givenAdminHasRole
        givenContractIsRegistered
    {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EXREG_ROLE));

        vm.prank(notAdmin);
        exRegAdmin.deregisterContract("ohm");
    }

    function test_deregisterContract()
        public
        givenPolicyIsActivated
        givenAdminHasRole
        givenContractIsRegistered
    {
        // Deregister the contract
        vm.prank(admin);
        exRegAdmin.deregisterContract("ohm");

        // Assert values
        vm.expectRevert(EXREGv1.Params_InvalidName.selector);
        EXREG.getContract("ohm");
    }

    // getContract
    // when the policy is not active
    //  [X] it reverts
    // when the caller is not the admin
    //  [X] it returns the contract address
    // [X] it returns the contract address

    function test_getContract_policyNotActive_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ExternalRegistryAdmin.OnlyPolicyActive.selector));

        exRegAdmin.getContract("ohm");
    }

    function test_getContract_notAdmin()
        public
        givenPolicyIsActivated
        givenAdminHasRole
        givenContractIsRegistered
    {
        vm.prank(notAdmin);
        address contractAddress = exRegAdmin.getContract("ohm");

        // Assert values
        assertEq(contractAddress, ohm, "contract address");
    }

    function test_getContract()
        public
        givenPolicyIsActivated
        givenAdminHasRole
        givenContractIsRegistered
    {
        vm.prank(admin);
        address contractAddress = exRegAdmin.getContract("ohm");

        // Assert values
        assertEq(contractAddress, ohm, "contract address");
        assertEq(EXREG.getContract("ohm"), ohm, "EXREG: contract address");
    }

    // getContractNames
    // when the policy is not active
    //  [X] it reverts
    // when the caller is not the admin
    //  [X] it returns the contract names
    // [X] it returns the contract names

    function test_getContractNames_policyNotActive_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ExternalRegistryAdmin.OnlyPolicyActive.selector));

        exRegAdmin.getContractNames();
    }

    function test_getContractNames_notAdmin()
        public
        givenPolicyIsActivated
        givenAdminHasRole
        givenContractIsRegistered
    {
        vm.prank(notAdmin);
        bytes5[] memory contractNames = exRegAdmin.getContractNames();

        // Assert values
        assertEq(contractNames.length, 1, "contract names length");
        assertEq(contractNames[0], "ohm", "contract name");
    }

    function test_getContractNames()
        public
        givenPolicyIsActivated
        givenAdminHasRole
        givenContractIsRegistered
    {
        bytes5[] memory contractNames = exRegAdmin.getContractNames();

        // Assert values
        assertEq(contractNames.length, 1, "contract names length");
        assertEq(contractNames[0], "ohm", "contract name");
    }
}
