// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {Actions, Kernel, Keycode, Policy} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";

contract BurnerLoansConfigTimelockConfigureDependenciesTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-DEPENDENCIES-I01.
    function test_givenMissingOrUnsupportedRoles_whenDependenciesConfigured_reverts(
        address caller_,
        uint8 major_
    ) public {
        Kernel empty = new Kernel();
        vm.prank(address(_kernel));
        _timelock.changeKernel(empty);
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, bytes5("ROLES"))
        );
        vm.prank(caller_);
        _timelock.configureDependencies();
        vm.prank(address(empty));
        _timelock.changeKernel(_kernel);
        vm.assume(major_ != 1);
        vm.mockCall(
            address(_roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, uint8(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_InvalidModuleVersion.selector
            )
        );
        vm.prank(caller_);
        _timelock.configureDependencies();
        assertEq(
            address(_timelock.ROLES()),
            address(_roles),
            "Rejected hook preserves cached ROLES"
        );
    }

    // Scenarios: BLCT-DEPENDENCIES-P01.
    function test_givenCompatibleRoles_whenDependenciesRefreshed_thenExactKeyAndPointer(
        address caller_
    ) public {
        vm.prank(caller_);
        Keycode[] memory keys = _timelock.configureDependencies();
        assertEq(keys.length, 1, "One dependency");
        assertEq(Keycode.unwrap(keys[0]), bytes5("ROLES"), "ROLES keycode");
        vm.prank(caller_);
        _timelock.configureDependencies();
        OlympusRoles replacement = new OlympusRoles(_kernel);
        _kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.prank(caller_);
        _timelock.configureDependencies();
        assertEq(address(_timelock.ROLES()), address(replacement), "Replacement cache refreshed");
    }
}
