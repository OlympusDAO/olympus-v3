// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";

// Contracts
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";
import {Keycode, Policy} from "src/Kernel.sol";

contract DepositManagerConfigTimelockConfigureDependenciesTest is DepositManagerConfigTimelockTest {
    bytes5 private constant _ROLES_KEYCODE = "ROLES";

    // Scenarios: DMCT-DEPENDENCIES-P01.
    function test_whenDependenciesConfigured(address caller_, uint8 minor_) public {
        vm.mockCall(
            address(roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(uint8(1), minor_)
        );
        bytes32 targetBefore = _targetState();
        vm.prank(caller_);
        Keycode[] memory dependencies = _configTimelock.configureDependencies();
        assertEq(dependencies.length, 1, "one dependency");
        assertEq(Keycode.unwrap(dependencies[0]), _ROLES_KEYCODE, "ROLES keycode");
        assertEq(address(_configTimelock.ROLES()), address(roles), "ROLES bound from Kernel");
        assertEq(_targetState(), targetBefore, "framework setup preserves target");
    }

    // Scenarios: DMCT-DEPENDENCIES-L01.
    function test_givenPausedInactive_whenDependenciesConfigured(address caller_) public {
        _pausePolicy(address(_configTimelock));
        _setPolicyActive(address(_configTimelock), false);
        vm.prank(caller_);
        Keycode[] memory dependencies = _configTimelock.configureDependencies();
        assertEq(dependencies.length, 1, "configuration remains available");
        assertFalse(_configTimelock.isEnabled(), "configuration does not enable");
        assertFalse(_configTimelock.isActive(), "configuration does not activate");
    }

    // Scenarios: DMCT-DEPENDENCIES-I01.
    function test_givenRolesMissing_whenConfigured_reverts() public {
        vm.mockCall(
            address(kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", _ROLES_KEYCODE),
            abi.encode(address(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, _ROLES_KEYCODE)
        );
        _configTimelock.configureDependencies();
    }

    // Scenarios: DMCT-DEPENDENCIES-I02.
    function test_whenRolesMajorUnsupported_reverts(uint8 major_, uint8 minor_) public {
        vm.assume(major_ != 1);
        vm.mockCall(
            address(roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, minor_)
        );
        vm.expectRevert(
            IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidModuleVersion.selector
        );
        _configTimelock.configureDependencies();
    }

    // Scenarios: DMCT-DEPENDENCIES-I02.
    function test_whenRolesMajorBoundarySeeds_reverts() public {
        _unsupportedRoles(0);
        _unsupportedRoles(2);
        _unsupportedRoles(type(uint8).max);
    }

    function _unsupportedRoles(uint8 major_) private {
        vm.mockCall(
            address(roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, uint8(0))
        );
        vm.expectRevert(
            IDepositManagerConfigTimelock.DepositManagerConfigTimelock_InvalidModuleVersion.selector
        );
        _configTimelock.configureDependencies();
    }
}
