// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Contracts
import {Actions, Keycode, Kernel, Policy, toKeycode} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {CCIPBridgeConfig} from "src/policies/bridge/CCIPBridgeConfig.sol";
import {ICCIPBridgeConfig} from "src/policies/interfaces/bridge/ICCIPBridgeConfig.sol";
import {MockRolesModule} from "src/test/policies/bridge/mocks/MockRolesModule.sol";

import {CCIPBridgeConfigTest} from "./CCIPBridgeConfigTest.sol";

contract CCIPBridgeConfigTests_configureDependencies is CCIPBridgeConfigTest {
    // given the kernel has no ROLES module installed
    //   [X] it reverts with Policy_ModuleDoesNotExist("ROLES")
    // Requires a fresh kernel without modules and a config instance deployed against it
    function test_givenRolesModuleNotInstalled_reverts() public {
        Kernel emptyKernel = new Kernel();
        vm.label(address(emptyKernel), "emptyKernel");
        CCIPBridgeConfig freshConfig = new CCIPBridgeConfig(
            emptyKernel,
            address(pool),
            GRACE_PERIOD
        );
        vm.label(address(freshConfig), "emptyKernelConfig");

        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        freshConfig.configureDependencies();
    }

    // given the installed ROLES module reports a major version other than 1
    //   [X] it reverts with CCIPBridgeConfig_InvalidModuleVersion
    //   [X] it leaves the previous ROLES pointer unchanged
    // Requires the MockRolesModule mock, installed through the kernel executor. The ROLES
    // write before the version read must roll back with the revert.
    function test_givenRolesModuleMajorVersionIsNot1_reverts() public {
        // The instance is deployed against a kernel of its own and never activated, so the
        // module swap does not reconfigure it and the direct call is observable
        Kernel freshKernel = new Kernel();
        vm.label(address(freshKernel), "freshKernel");
        OlympusRoles freshRoles = new OlympusRoles(freshKernel);
        vm.label(address(freshRoles), "freshRolesModule");
        freshKernel.executeAction(Actions.InstallModule, address(freshRoles));

        CCIPBridgeConfig freshConfig = new CCIPBridgeConfig(
            freshKernel,
            address(pool),
            GRACE_PERIOD
        );
        vm.label(address(freshConfig), "freshKernelConfig");
        freshConfig.configureDependencies();
        assertEq(
            address(freshConfig.ROLES()),
            address(freshRoles),
            "the ROLES pointer should be the major version 1 module"
        );

        MockRolesModule wrongVersionRoles = new MockRolesModule(freshKernel);
        vm.label(address(wrongVersionRoles), "wrongVersionRolesModule");
        freshKernel.executeAction(Actions.UpgradeModule, address(wrongVersionRoles));

        vm.expectRevert(
            abi.encodeWithSelector(ICCIPBridgeConfig.CCIPBridgeConfig_InvalidModuleVersion.selector)
        );
        freshConfig.configureDependencies();

        assertEq(
            address(freshConfig.ROLES()),
            address(freshRoles),
            "the ROLES pointer should roll back to the previous module"
        );
    }

    // when the caller is any address
    //   [X] it returns a one-element array holding the ROLES keycode
    //   [X] it points ROLES at the installed module
    // The hook carries no caller restriction; the fuzz proves execution does not depend on the
    // kernel being the caller.
    function test_whenCallerIsAnyAddress(address caller_) public {
        vm.prank(caller_);
        Keycode[] memory dependencies = config.configureDependencies();

        assertEq(dependencies.length, 1, "the dependency array should hold one keycode");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "the dependency should be the ROLES keycode"
        );
        assertEq(
            address(config.ROLES()),
            address(rolesModule),
            "the ROLES pointer should be the installed module"
        );
    }

    // given the ROLES module was upgraded in the kernel
    //   [X] it repoints ROLES at the new module
    // The kernel's UpgradeModule action auto-reconfigures its dependents, so an activated
    // policy is repointed before any direct call. To prove the direct-call refresh, use a
    // fresh unactivated config (not a kernel dependent): install ROLES, call directly,
    // upgrade the module, call directly again.
    function test_givenRolesModuleUpgraded() public {
        Kernel freshKernel = new Kernel();
        vm.label(address(freshKernel), "freshKernel");
        OlympusRoles firstRoles = new OlympusRoles(freshKernel);
        vm.label(address(firstRoles), "firstRolesModule");
        freshKernel.executeAction(Actions.InstallModule, address(firstRoles));

        CCIPBridgeConfig freshConfig = new CCIPBridgeConfig(
            freshKernel,
            address(pool),
            GRACE_PERIOD
        );
        vm.label(address(freshConfig), "freshKernelConfig");
        freshConfig.configureDependencies();
        assertEq(
            address(freshConfig.ROLES()),
            address(firstRoles),
            "the ROLES pointer should be the first module"
        );

        OlympusRoles secondRoles = new OlympusRoles(freshKernel);
        vm.label(address(secondRoles), "secondRolesModule");
        freshKernel.executeAction(Actions.UpgradeModule, address(secondRoles));
        assertEq(
            address(freshConfig.ROLES()),
            address(firstRoles),
            "the unactivated instance should not be reconfigured by the upgrade"
        );

        freshConfig.configureDependencies();

        assertEq(
            address(freshConfig.ROLES()),
            address(secondRoles),
            "the ROLES pointer should be the upgraded module"
        );
    }

    // given the policy was deactivated in the kernel
    //   [X] the cached ROLES pointer is unchanged
    //   [X] a role-gated function still authorizes against the cached module
    // No isPolicyActive check exists anywhere in the policy; deactivation does not sever the
    // role wiring. Pins the absent guard as documented behavior.
    function test_givenPolicyDeactivatedInKernel() public givenPolicyDeactivatedInKernel {
        assertFalse(config.isActive(), "the policy should be deactivated in the kernel");
        assertEq(
            address(config.ROLES()),
            address(rolesModule),
            "the ROLES pointer should stay cached after the deactivation"
        );

        vm.prank(admin);
        config.enable("");

        assertTrue(
            config.isEnabled(),
            "the admin role should still authorize through the cached module"
        );
    }
}
