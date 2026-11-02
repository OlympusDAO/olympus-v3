// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCollateralTest} from "./BurnerLoansCollateralTest.sol";
import {Actions, Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {BurnerLoansCollateral} from "src/policies/burnerloans/BurnerLoansCollateral.sol";

// Sequential fixture calls intentionally ignore values already checked by their helper.
// forge-lint: disable-start(unused-return,reentrancy-no-eth,calls-loop,literal-instead-of-constant)
contract BurnerLoansCollateralConfigureDependenciesTest is BurnerLoansCollateralTest {
    bytes5 internal constant _ROLES_KEYCODE = "ROLES";

    // Scenarios: BLCOL-DEPENDENCIES-P01.
    function test_givenReplacementRoles_whenConfigured_thenCachedPointerRefreshes(
        address caller_
    ) public {
        OlympusRoles replacement = new OlympusRoles(kernel);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.prank(caller_);
        Keycode[] memory dependencies = _collateral.configureDependencies();
        assertEq(dependencies.length, 1, "Only ROLES is required");
        assertEq(Keycode.unwrap(dependencies[0]), _ROLES_KEYCODE, "Exact ordered keycode");
        assertEq(
            address(_collateral.ROLES()),
            address(replacement),
            "Cache tracks replacement ROLES"
        );
        assertFalse(
            replacement.hasRole(address(this), ADMIN_ROLE),
            "Old module's grants are not retained"
        );
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-DEPENDENCIES-P01, BLCOL-DEPENDENCIES-P03.
    function test_givenUnvalidatedModuleMajor_whenFirstAndRepeatedConfiguration_thenNoVersionRead(
        address caller_
    ) public {
        BurnerLoansCollateral fresh = new BurnerLoansCollateral(kernel, _core);
        vm.mockCall(
            address(roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(uint8(255), uint8(255))
        );
        vm.expectCall(address(roles), abi.encodeWithSignature("VERSION()"), uint64(0));
        vm.prank(caller_);
        Keycode[] memory dependencies = fresh.configureDependencies();
        assertEq(dependencies.length, 1, "One first-call dependency");
        assertEq(Keycode.unwrap(dependencies[0]), _ROLES_KEYCODE, "First-call ROLES keycode");
        assertEq(address(fresh.ROLES()), address(roles), "First call initializes cached ROLES");
        vm.prank(caller_);
        dependencies = fresh.configureDependencies();
        assertEq(dependencies.length, 1, "Repeated configuration remains valid");
        assertEq(address(fresh.ROLES()), address(roles), "No version validation is invented");
        assertFalse(fresh.isEnabled(), "Dependency setup does not enable a fresh action");
        assertFalse(
            kernel.isPolicyActive(fresh),
            "Dependency setup does not activate a fresh action"
        );
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-DEPENDENCIES-P02.
    function test_givenMissingRoles_whenConfigured_thenPreviousCachePreserved(
        address caller_,
        bool enabled_
    ) public givenCollateralEnabled {
        _setPolicyState(_collateral, true, enabled_);
        address previous = address(_collateral.ROLES());
        Kernel empty = new Kernel();
        vm.prank(address(kernel));
        _collateral.changeKernel(empty);
        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES"))
        );
        vm.prank(caller_);
        _collateral.configureDependencies();
        assertEq(
            address(_collateral.ROLES()),
            previous,
            "Failed lookup preserves previous module cache"
        );
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-DEPENDENCIES-P01.
    function test_whenDependenciesConfigured_thenRolesIsResolved(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenCollateralEnabled {
        _setPolicyState(_collateral, active_, enabled_);
        vm.prank(caller_);
        Keycode[] memory dependencies = _collateral.configureDependencies();
        assertEq(dependencies.length, 1, "One module dependency");
        assertEq(Keycode.unwrap(dependencies[0]), _ROLES_KEYCODE, "ROLES dependency");
        vm.prank(caller_);
        dependencies = _collateral.configureDependencies();
        assertEq(dependencies.length, 1, "Repeat configuration is supported");
        assertEq(_collateral.core(), address(_core), "No Core rebinding");
        _assertAccountingPreserved();
    }
}

// forge-lint: disable-end(unused-return,reentrancy-no-eth,calls-loop,literal-instead-of-constant)
