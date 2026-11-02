// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansSeize} from "src/policies/burnerloans/BurnerLoansSeize.sol";
import {Actions, Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {BurnerLoansSeizeLifecycleTest} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeLifecycleTest.sol";

// Fixture casts are bounded; seed loops intentionally call external contracts.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// forge-lint: disable-start(unsafe-typecast, unused-return)

contract BurnerLoansSeizeConfigureDependenciesTest is BurnerLoansSeizeLifecycleTest {
    // Scenarios: BLLIQ-DEPENDENCIES-P01.
    function test_whenDependenciesConfigured_thenRolesIsResolved(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_liquidation, active_, enabled_);
        vm.prank(caller_);
        Keycode[] memory dependencies = _liquidation.configureDependencies();
        assertEq(dependencies.length, 1, "One module dependency");
        assertEq(Keycode.unwrap(dependencies[0]), bytes5("ROLES"), "ROLES dependency");
        vm.prank(caller_);
        dependencies = _liquidation.configureDependencies();
        assertEq(dependencies.length, 1, "Repeat configuration is supported");
        assertEq(_liquidation.core(), address(_core), "No Core rebinding");
        assertEq(
            address(_liquidation.ROLES()),
            address(_roles),
            "Resolved ROLES cache matches the Kernel module"
        );
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DEPENDENCIES-P02.
    function test_givenRolesMissing_whenConfigured_reverts(address caller_) public {
        Kernel empty = new Kernel();
        vm.prank(address(_kernel));
        _liquidation.changeKernel(empty);
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        vm.prank(caller_);
        _liquidation.configureDependencies();
        assertEq(
            address(_liquidation.ROLES()),
            address(_roles),
            "Missing module leaves prior cache intact"
        );
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DEPENDENCIES-P01.
    function test_givenFreshAction_whenConfigured_thenInitialCacheResolved(address caller_) public {
        _liquidation = new BurnerLoansSeize(_kernel, _core);
        assertEq(address(_liquidation.ROLES()), address(0), "Constructor has no cached module");
        vm.prank(caller_);
        _liquidation.configureDependencies();
        assertEq(
            address(_liquidation.ROLES()),
            address(_roles),
            "Permissionless first configuration resolves ROLES"
        );
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DEPENDENCIES-P01.
    function test_givenReplacementRoles_whenConfigured_thenCacheRefreshed(address caller_) public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        OlympusRoles replacement = new OlympusRoles(_kernel);
        _kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.prank(caller_);
        _liquidation.configureDependencies();
        assertEq(
            address(_liquidation.ROLES()),
            address(replacement),
            "Configuration refreshes module pointer"
        );
        assertFalse(_liquidation.isActive(), "Configuration does not reactivate subject");
        _assertLoansPreserved();
    }
}

// forge-lint: disable-end(unsafe-typecast, unused-return)
