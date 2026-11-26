// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(literal-instead-of-constant,unused-return)

// Interfaces

import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventorySetConfigOperatorTest is BurnerLoansInventoryTest {
    // Scenarios: BLINV-CONFIGURATOR-A06, BLINV-CONFIGURATOR-D02, BLINV-CONFIGURATOR-D03, BLINV-CONFIGURATOR-D04, BLINV-CONFIGURATOR-D05, BLINV-CONFIGURATOR-P01, BLINV-CONFIGURATOR-P02, BLINV-CONFIGURATOR-P05.
    function test_whenDistinctControllerSelected(
        address candidate_,
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        vm.assume(candidate_ != address(0));
        _givenInitialLifecycle(true, enabled_);
        _setPolicyActive(address(facility), coreActive_);
        _mockFacilityEnabled(coreEnabled_);
        bytes32 beforeState = _accountingState();
        vm.expectEmit(true, false, false, true, address(inventory));
        emit IConfigOperator.ConfigOperatorSet(candidate_);
        vm.prank(admin);
        inventory.setConfigOperator(candidate_);
        assertEq(inventory.configOperator(), candidate_, "Exact selected authority");
        assertEq(inventory.isEnabled(), enabled_, "Lifecycle unchanged");
        assertEq(_accountingState(), beforeState, "Accounting unchanged");
    }

    // Scenarios: BLINV-CONFIGURATOR-A03.
    function test_givenControllerWithoutUsableViews_whenSelected_succeeds() public {
        vm.mockCallRevert(address(config), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.mockCallRevert(address(config), abi.encodeWithSignature("facility()"), hex"deadbeef");
        test_whenDistinctControllerSelected(address(config), false, true, true);
    }

    // Scenarios: BLINV-CONFIGURATOR-A04.
    function test_givenController_whenCleared() public {
        vm.prank(admin);
        inventory.setConfigOperator(address(config));
        vm.expectEmit(true, false, false, true, address(inventory));
        emit IConfigOperator.ConfigOperatorSet(address(0));
        vm.prank(admin);
        inventory.setConfigOperator(address(0));
        assertEq(inventory.configOperator(), address(0), "Delegation cleared");
        ohm.mint(address(inventory), 1);
        vm.prank(admin);
        inventory.rescueSurplus();
        assertEq(ohm.balanceOf(address(trsry)), 1, "ADMIN recovery retained");
    }

    // Scenarios: BLINV-CONFIGURATOR-A02, BLINV-CONFIGURATOR-I01.
    function test_whenUnchangedController_reverts(bool nonzero_) public {
        address candidate = nonzero_ ? address(config) : address(0);
        if (nonzero_) {
            vm.prank(admin);
            inventory.setConfigOperator(candidate);
        }
        bytes32 beforeState = _accountingState();
        vm.expectRevert(abi.encodeWithSelector(IConfigOperator.ConfigOperator_Unchanged.selector));
        vm.prank(admin);
        inventory.setConfigOperator(candidate);
        assertEq(inventory.configOperator(), candidate, "Controller unchanged");
        assertEq(_accountingState(), beforeState, "Accounting unchanged");
    }

    // Scenarios: BLINV-CONFIGURATOR-A05.
    function test_whenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        bytes32 beforeState = _accountingState();
        _expectAdminRole();
        vm.prank(caller_);
        inventory.setConfigOperator(address(config));
        assertEq(inventory.configOperator(), address(0), "No authority write");
        assertEq(_accountingState(), beforeState, "Accounting unchanged");
    }

    // Scenarios: BLINV-CONFIGURATOR-L01, BLINV-CONFIGURATOR-L02.
    function test_givenInactiveInventory_whenSelected_reverts(bool enabled_) public {
        _givenInitialLifecycle(true, enabled_);
        _deactivateInventory();
        _expectInventoryNotActive();
        vm.prank(admin);
        inventory.setConfigOperator(address(config));
        assertEq(inventory.configOperator(), address(0), "No authority write");
        _reactivateInventory();
        vm.prank(admin);
        inventory.setConfigOperator(address(config));
        assertEq(inventory.configOperator(), address(config), "Authority recovers");
    }

    // Scenarios: BLINV-CONFIGURATOR-A02, BLINV-CONFIGURATOR-A05, BLINV-CONFIGURATOR-I01, BLINV-CONFIGURATOR-P05.
    function test_whenControllerBoundarySeeds() public {
        test_whenUnauthorizedCaller_reverts(address(facility));
        test_whenUnauthorizedCaller_reverts(address(config));
        test_whenUnauthorizedCaller_reverts(burnerLoansAdmin);
        test_whenUnchangedController_reverts(false);
        test_whenDistinctControllerSelected(outsider, true, false, false);
        test_whenUnchangedController_reverts(true);
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unused-return)
