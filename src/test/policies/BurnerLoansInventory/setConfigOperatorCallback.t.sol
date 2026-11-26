// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(literal-instead-of-constant,unused-return)

// Interfaces

// Libraries

// Contracts

import {BurnerLoansInventoryCallbackTest} from "./fixtures/BurnerLoansInventoryCallbackTest.sol";

contract BurnerLoansInventorySetConfigOperatorCallbackTest is BurnerLoansInventoryCallbackTest {
    // Scenarios: BLINV-CONFIGURATOR-C01.
    function test_givenOperatorCallback_whenRejectionCaught_succeeds() public {
        _prepareSupply(10);
        _token.arm(
            ohm.transferFrom.selector,
            address(inventory),
            abi.encodeCall(inventory.setConfigOperator, (outsider)),
            false
        );
        vm.prank(provider);
        inventory.supply(10);
        assertEq(inventory.configOperator(), address(config), "No nested operator write");
        _assertNestedRejected();
        assertEq(inventory.suppliedIdleOhm(), 117, "Outer supply completes once");
    }

    // Scenarios: BLINV-CONFIGURATOR-C02.
    function test_givenOperatorCallback_whenRejectionPropagates_reverts() public {
        _prepareSupply(10);
        bytes32 beforeState = _accountingState();
        _token.arm(
            ohm.transferFrom.selector,
            address(inventory),
            abi.encodeCall(inventory.setConfigOperator, (outsider)),
            true
        );
        _expectPropagatedRejection();
        vm.prank(provider);
        inventory.supply(10);
        assertEq(inventory.configOperator(), address(config), "No nested operator write");
        assertEq(_accountingState(), beforeState, "Outer supply rolls back");
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unused-return)
