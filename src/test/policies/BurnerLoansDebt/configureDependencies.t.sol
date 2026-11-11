// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {BurnerLoansDebtLifecycleTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtLifecycleTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(unsafe-typecast, unused-return)

contract BurnerLoansDebtConfigureDependenciesTest is BurnerLoansDebtLifecycleTest {
    // Scenarios: BLDEBT-DEPENDENCIES-P01.
    function test_whenDependenciesConfigured_thenRolesIsResolved(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_debt, active_, enabled_);
        vm.prank(caller_);
        Keycode[] memory dependencies = _debt.configureDependencies();
        assertEq(dependencies.length, 1, "One module dependency");
        assertEq(Keycode.unwrap(dependencies[0]), bytes5("ROLES"), "ROLES dependency");
        vm.prank(caller_);
        dependencies = _debt.configureDependencies();
        assertEq(dependencies.length, 1, "Repeat configuration is supported");
        assertEq(_debt.core(), address(_core), "No Core rebinding");
        assertEq(
            address(_debt.ROLES()),
            address(_roles),
            "Resolved ROLES cache matches the Kernel module"
        );
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-DEPENDENCIES-P02.
    function test_givenRolesMissing_whenConfigured_reverts(address caller_) public {
        Kernel empty = new Kernel();
        vm.prank(address(_kernel));
        _debt.changeKernel(empty);
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        vm.prank(caller_);
        _debt.configureDependencies();
        _assertLoansPreserved();
    }
}

// forge-lint: disable-end(unsafe-typecast, unused-return)
