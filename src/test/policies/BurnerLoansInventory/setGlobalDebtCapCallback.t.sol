// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces

// Libraries

// Contracts

import {BurnerLoansInventoryCallbackTest} from "./fixtures/BurnerLoansInventoryCallbackTest.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.

contract BurnerLoansInventorySetGlobalDebtCapCallbackTest is BurnerLoansInventoryCallbackTest {
    // Scenarios: BLINV-GLOBAL-CAP-C01.
    function test_givenCapCallback_whenRejectionCaught_succeeds() public {
        _prepareSupply(10);
        _token.arm(
            ohm.transferFrom.selector,
            address(inventory),
            abi.encodeCall(inventory.setGlobalDebtCap, (2000)),
            false
        );
        vm.prank(provider);
        inventory.supply(10);
        assertEq(inventory.globalDebtCapOhm(), 1000, "No nested cap write");
        _assertNestedRejected();
        assertEq(inventory.suppliedIdleOhm(), 117, "Outer supply completes once");
    }

    // Scenarios: BLINV-GLOBAL-CAP-C01.
    function test_givenCapCallback_whenRejectionPropagates_reverts() public {
        _prepareSupply(10);
        bytes32 beforeState = _accountingState();
        _token.arm(
            ohm.transferFrom.selector,
            address(inventory),
            abi.encodeCall(inventory.setGlobalDebtCap, (2000)),
            true
        );
        _expectPropagatedRejection();
        vm.prank(provider);
        inventory.supply(10);
        assertEq(inventory.globalDebtCapOhm(), 1000, "No nested cap write");
        assertEq(_accountingState(), beforeState, "Outer supply rolls back");
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
