// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Contracts
import {PriceCacherTaskLifecycleTest} from "./fixtures/PriceCacherTaskLifecycleTest.sol";
import {Policy, Keycode} from "src/Kernel.sol";

contract PriceCacherTaskConfigureDependenciesTest is PriceCacherTaskLifecycleTest {
    // Scenarios: PCACHER-DEPENDENCIES-P01.
    function test_whenDependenciesConfigured(address caller_) public {
        bytes32 beforeState = _preservedState();
        vm.prank(caller_);
        Keycode[] memory dependencies = cacher.configureDependencies();
        assertEq(dependencies.length, 1, "dependency count");
        assertEq(Keycode.unwrap(dependencies[0]), bytes5("ROLES"), "ROLES dependency");
        assertEq(address(cacher.ROLES()), address(roles), "cached ROLES binding");
        assertEq(_preservedState(), beforeState, "reconfiguration preserves existing data");
    }

    // Scenarios: PCACHER-DEPENDENCIES-P02.
    function test_givenUnconfigured_whenDependenciesConfigured(address caller_) public {
        _freshSubject(false);
        vm.prank(caller_);
        Keycode[] memory dependencies = cacher.configureDependencies();
        assertEq(dependencies.length, 1, "dependency count");
        assertEq(address(cacher.ROLES()), address(roles), "ROLES binding initialized");
        assertFalse(cacher.isEnabled(), "configuration does not enable");
        assertFalse(cacher.isActive(), "configuration does not activate");
    }

    // Scenarios: PCACHER-DEPENDENCIES-I01.
    function test_givenMissingRoles_whenConfigured_reverts() public {
        vm.mockCall(
            address(kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("ROLES")),
            abi.encode(address(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, bytes5("ROLES"))
        );
        cacher.configureDependencies();
    }

    // Scenarios: PCACHER-DEPENDENCIES-L01.
    function test_givenPaused_whenConfigured(address caller_) public givenLifecycleDisabled {
        test_whenDependenciesConfigured(caller_);
        assertFalse(cacher.isEnabled(), "configuration preserves pause");
    }

    // Scenarios: PCACHER-DEPENDENCIES-L02.
    function test_givenInactive_whenConfigured(address caller_) public givenLifecycleInactive {
        test_whenDependenciesConfigured(caller_);
        assertFalse(cacher.isActive(), "configuration does not reactivate");
    }

    // Scenarios: PCACHER-DEPENDENCIES-I02.
    function test_whenUnsupportedRolesVersion_reverts(
        uint8 major_,
        uint8 minor_,
        address caller_
    ) public {
        vm.assume(major_ != 1);
        vm.mockCall(
            address(roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, minor_)
        );
        _expectConfigRejected(
            caller_,
            abi.encodeCall(cacher.configureDependencies, ()),
            abi.encodeWithSelector(
                Policy.Policy_WrongModuleVersion.selector,
                abi.encode([uint8(1)])
            )
        );
    }

    // Scenarios: PCACHER-DEPENDENCIES-I02.
    function test_whenRolesVersionBoundarySeeds_reverts() public {
        test_whenUnsupportedRolesVersion_reverts(0, 0, address(0));
        test_whenUnsupportedRolesVersion_reverts(2, type(uint8).max, admin);
        test_whenUnsupportedRolesVersion_reverts(type(uint8).max, type(uint8).max, heart);
    }
}
