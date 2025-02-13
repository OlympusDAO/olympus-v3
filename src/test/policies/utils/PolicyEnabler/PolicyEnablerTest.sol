// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {Kernel, Actions} from "src/Kernel.sol";

import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {MockPolicyEnabler, MockPolicyEnablerWithCustomLogic} from "./MockPolicyEnabler.sol";

contract PolicyEnablerTest is Test {
    address public constant EMERGENCY = address(0xAAAA);
    address public constant ADMIN = address(0xBBBB);

    Kernel public kernel;
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;
    MockPolicyEnabler public policyEnabler;
    MockPolicyEnablerWithCustomLogic public policyEnablerWithCustomLogic;

    uint256 public enableValue;
    uint256 public disableValue;
    uint256 public disableAnotherValue;

    bytes public enableData;
    bytes public disableData;

    function setUp() public {
        kernel = new Kernel();
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        policyEnabler = new MockPolicyEnabler(kernel);

        // Install
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(policyEnabler));

        // Grant roles
        rolesAdmin.grantRole(ADMIN_ROLE, ADMIN);
        rolesAdmin.grantRole(EMERGENCY_ROLE, EMERGENCY);
    }

    modifier givenPolicyHasCustomLogic() {
        policyEnabler = new MockPolicyEnablerWithCustomLogic(kernel);

        kernel.executeAction(Actions.ActivatePolicy, address(policyEnabler));

        _;
    }

    modifier givenPolicyEnableCustomLogicReverts() {
        (MockPolicyEnablerWithCustomLogic(address(policyEnabler))).setEnableShouldRevert(true);
        _;
    }

    modifier givenPolicyDisableCustomLogicReverts() {
        (MockPolicyEnablerWithCustomLogic(address(policyEnabler))).setDisableShouldRevert(true);
        _;
    }

    modifier givenEnabled() {
        vm.prank(EMERGENCY);
        policyEnabler.enable(enableData);
        _;
    }

    modifier givenDisabled() {
        vm.prank(EMERGENCY);
        policyEnabler.disable(disableData);
        _;
    }

    modifier givenEnableData(uint256 value_) {
        enableValue = value_;

        enableData = abi.encode(MockPolicyEnablerWithCustomLogic.EnableData({value: value_}));
        _;
    }

    modifier givenDisableData(uint256 value_, uint256 anotherValue_) {
        disableValue = value_;
        disableAnotherValue = anotherValue_;

        disableData = abi.encode(
            MockPolicyEnablerWithCustomLogic.DisableData({
                value: value_,
                anotherValue: anotherValue_
            })
        );
        _;
    }

    function _assertStateVariables(
        bool isEnabled_,
        uint256 expectedEnableValue_,
        uint256 expectedDisableValue_,
        uint256 expectedDisableAnotherValue_
    ) internal view {
        // Assert enabled
        assertEq(policyEnabler.isEnabled(), isEnabled_, "isEnabled");

        // Enable
        assertEq(policyEnabler.enableValue(), expectedEnableValue_, "enableValue");

        // Disable
        assertEq(policyEnabler.disableValue(), expectedDisableValue_, "disableValue");
        assertEq(
            policyEnabler.disableAnotherValue(),
            expectedDisableAnotherValue_,
            "disableAnotherValue"
        );
    }
}
