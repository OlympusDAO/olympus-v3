// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Interfaces
import {ICCIPTokenPoolConfigTimelock} from "src/policies/interfaces/bridge/ICCIPTokenPoolConfigTimelock.sol";

// Contracts
import {Actions, Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {CCIPTokenPoolConfigTimelock} from "src/policies/bridge/CCIPTokenPoolConfigTimelock.sol";
import {MockRolesModule} from "src/test/policies/bridge/mocks/MockRolesModule.sol";

import {CCIPTokenPoolConfigTimelockTest} from "./CCIPTokenPoolConfigTimelockTest.sol";

contract CCIPTokenPoolConfigTimelockTests_configureDependencies is CCIPTokenPoolConfigTimelockTest {
    // given the kernel has no ROLES module installed
    //   [X] it reverts with Policy_ModuleDoesNotExist("ROLES")
    // Requires the fresh-kernel stack helper: a kernel without ROLES, a config on it and an
    // unactivated timelock over that config
    function test_givenRolesModuleNotInstalled_reverts() public {
        (, , CCIPTokenPoolConfigTimelock foreignTimelock) = _deployStackOnForeignKernel();

        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        foreignTimelock.configureDependencies();
    }

    // given the installed ROLES module reports a major version other than one
    //   [X] it reverts with CCIPTokenPoolConfigTimelock_InvalidModuleVersion
    //   [X] it leaves the previously cached ROLES pointer unchanged
    // Requires MockRolesModule installed through the kernel executor. The ROLES write before
    // the version read rolls back with the revert.
    function test_givenRolesModuleMajorVersionIsNot1_reverts() public {
        // The stack is deployed against a kernel of its own and never activated, so the module
        // swap does not reconfigure it and the direct call is observable
        Kernel freshKernel = new Kernel();
        vm.label(address(freshKernel), "freshKernel");
        OlympusRoles freshRoles = new OlympusRoles(freshKernel);
        vm.label(address(freshRoles), "freshRolesModule");
        freshKernel.executeAction(Actions.InstallModule, address(freshRoles));

        (, CCIPTokenPoolConfigTimelock freshTimelock) = _deployStackOnKernel(freshKernel);
        freshTimelock.configureDependencies();
        assertEq(
            address(freshTimelock.ROLES()),
            address(freshRoles),
            "the ROLES pointer should be the major version one module"
        );

        MockRolesModule wrongVersionRoles = new MockRolesModule(freshKernel);
        vm.label(address(wrongVersionRoles), "wrongVersionRolesModule");
        freshKernel.executeAction(Actions.UpgradeModule, address(wrongVersionRoles));

        vm.expectRevert(
            abi.encodeWithSelector(
                ICCIPTokenPoolConfigTimelock
                    .CCIPTokenPoolConfigTimelock_InvalidModuleVersion
                    .selector
            )
        );
        freshTimelock.configureDependencies();

        assertEq(
            address(freshTimelock.ROLES()),
            address(freshRoles),
            "the ROLES pointer should roll back to the previous module"
        );
    }

    // when the caller is any address
    //   [X] it returns a one-element array holding the ROLES keycode
    //   [X] it points ROLES at the installed module
    // The hook is deliberately unrestricted (base behavior); the fuzz pins that success does
    // not depend on the caller
    function test_whenCallerIsAnyAddress(address caller_) public {
        vm.assume(caller_ != address(0));

        vm.prank(caller_);
        Keycode[] memory dependencies = timelock.configureDependencies();

        assertEq(dependencies.length, 1, "the dependency array should hold one keycode");
        assertEq(
            Keycode.unwrap(dependencies[0]),
            Keycode.unwrap(toKeycode("ROLES")),
            "the dependency should be the ROLES keycode"
        );
        assertEq(
            address(timelock.ROLES()),
            address(rolesModule),
            "the ROLES pointer should be the installed module"
        );
    }

    // given the ROLES module has been upgraded in the kernel
    //   [X] it repoints ROLES at the new module on a direct call
    // Only observable on an unactivated instance against a fresh kernel: on an activated
    // policy the kernel's UpgradeModule reconfiguration already repoints every dependent
    // before any direct call could
    function test_givenRolesModuleUpgraded() public {
        Kernel freshKernel = new Kernel();
        vm.label(address(freshKernel), "freshKernel");
        OlympusRoles firstRoles = new OlympusRoles(freshKernel);
        vm.label(address(firstRoles), "firstRolesModule");
        freshKernel.executeAction(Actions.InstallModule, address(firstRoles));

        (, CCIPTokenPoolConfigTimelock freshTimelock) = _deployStackOnKernel(freshKernel);
        freshTimelock.configureDependencies();
        assertEq(
            address(freshTimelock.ROLES()),
            address(firstRoles),
            "the ROLES pointer should be the first module"
        );

        OlympusRoles secondRoles = new OlympusRoles(freshKernel);
        vm.label(address(secondRoles), "secondRolesModule");
        freshKernel.executeAction(Actions.UpgradeModule, address(secondRoles));
        assertEq(
            address(freshTimelock.ROLES()),
            address(firstRoles),
            "the unactivated instance should not be reconfigured by the upgrade"
        );

        freshTimelock.configureDependencies();

        assertEq(
            address(freshTimelock.ROLES()),
            address(secondRoles),
            "the ROLES pointer should be the upgraded module"
        );
    }

    // given the timelock policy has been deactivated in the kernel
    //   [X] it keeps the cached ROLES pointer
    //   [X] a role-gated function still consults the cached module
    // Pins the absent isPolicyActive guard: deactivation does not clear the wiring
    function test_givenPolicyDeactivatedInKernel() public givenPolicyDeactivatedInKernel {
        assertFalse(timelock.isActive(), "the timelock should be deactivated in the kernel");
        assertEq(
            address(timelock.ROLES()),
            address(rolesModule),
            "the ROLES pointer should stay cached after the deactivation"
        );

        vm.prank(admin);
        timelock.enable("");

        assertTrue(
            timelock.isEnabled(),
            "the admin role should still authorize through the cached module"
        );
    }

    // when requestPermissions is called
    //   [X] it returns an empty permissions array
    // The policy requests no module permissions; the pure answer cannot depend on the caller
    function test_requestPermissions_returnsEmptyArray() public {
        Permissions[] memory permissions = timelock.requestPermissions();

        assertEq(permissions.length, 0, "the policy should request no module permissions");
    }
}
