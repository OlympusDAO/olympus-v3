// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions, Keycode, Policy} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";

contract BurnerLoansCoreConfigureDependenciesTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-DEPENDENCIES-P01.
    function test_whenDependenciesRefreshed(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.prank(caller_);
        Keycode[] memory deps = _core.configureDependencies();
        assertEq(deps.length, 2, "Two dependencies");
        assertEq(Keycode.unwrap(deps[0]), bytes5("FLOAN"), "FLOAN first");
        assertEq(Keycode.unwrap(deps[1]), bytes5("ROLES"), "ROLES second");
        assertEq(_core.floan(), address(_floan), "FLOAN pointer bound");
        assertEq(address(_core.ROLES()), address(_roles), "ROLES pointer bound");
        assertEq(_state(), before, "Refresh preserves loans and lifecycle");
    }

    // Scenarios: BLCORE-DEPENDENCIES-I01.
    function test_givenFLOANMissing_whenConfigured_reverts(address caller_) public {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("FLOAN")),
            abi.encode(address(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, bytes5("FLOAN"))
        );
        vm.prank(caller_);
        _core.configureDependencies();
        assertEq(address(_core.ROLES()), address(_roles), "Failed refresh preserves ROLES");
        assertEq(_core.floan(), address(_floan), "Failed refresh preserves FLOAN");
    }

    // Scenarios: BLCORE-DEPENDENCIES-I01.
    function test_givenFLOANMajorUnsupported_whenConfigured_reverts(
        address caller_,
        uint8 major_
    ) public {
        vm.assume(major_ != 1);
        vm.mockCall(
            address(_floan),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, uint8(0))
        );
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidModuleVersion.selector);
        vm.prank(caller_);
        _core.configureDependencies();
        assertEq(address(_core.ROLES()), address(_roles), "Failed version refresh preserves ROLES");
    }

    // Scenarios: BLCORE-DEPENDENCIES-I01.
    function test_givenROLESMissing_whenConfigured_reverts(address caller_) public {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSignature("getModuleForKeycode(bytes5)", bytes5("ROLES")),
            abi.encode(address(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, bytes5("ROLES"))
        );
        vm.prank(caller_);
        _core.configureDependencies();
        assertEq(address(_core.ROLES()), address(_roles), "Failed refresh preserves ROLES");
        assertEq(_core.floan(), address(_floan), "Failed refresh preserves FLOAN");
    }

    // Scenarios: BLCORE-DEPENDENCIES-I01.
    function test_givenROLESMajorUnsupported_whenConfigured_reverts(
        address caller_,
        uint8 major_
    ) public {
        vm.assume(major_ != 1);
        vm.mockCall(
            address(_roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, uint8(0))
        );
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidModuleVersion.selector);
        vm.prank(caller_);
        _core.configureDependencies();
        assertEq(address(_core.ROLES()), address(_roles), "Failed version refresh preserves ROLES");
    }

    // Scenarios: BLCORE-DEPENDENCIES-P01.
    function test_givenModuleUpgrade_whenConfigured(address caller_) public {
        OlympusRoles roles = new OlympusRoles(_kernel);
        _kernel.executeAction(Actions.UpgradeModule, address(roles));
        vm.prank(caller_);
        _core.configureDependencies();
        assertEq(address(_core.ROLES()), address(roles), "Upgrade refreshes roles");
        assertEq(_core.floan(), address(_floan), "Other module preserved");
    }

    // Scenarios: BLCORE-DEPENDENCIES-P02.
    function test_givenBusyCore_whenConfigured_reverts() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("configureDependencies()"),
            false
        );
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Refresh cannot reenter Core"
        );
        assertEq(address(_core.ROLES()), address(_roles), "Busy refresh leaves cached modules");
    }
}
