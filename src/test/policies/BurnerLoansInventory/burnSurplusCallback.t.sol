// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant)

// Interfaces

// Libraries

// Contracts

import {BurnerLoansInventoryCallbackTest} from "./fixtures/BurnerLoansInventoryCallbackTest.sol";

contract BurnerLoansInventoryBurnSurplusCallbackTest is BurnerLoansInventoryCallbackTest {
    // Scenarios: BLINV-BURN-SURPLUS-C01.
    function test_givenBurnCallback_whenRejectionCaught_succeeds() public {
        ohm.mint(address(inventory), 10);
        _armWithdrawal(ohm.burnFrom.selector, false);

        vm.prank(admin);
        inventory.burnSurplus();
        assertEq(inventory.surplusOhm(), 0, "Surplus burned once");
        assertEq(inventory.suppliedIdleOhm(), 107, "Provider backing preserved");
        _assertNestedRejected();
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-BURN-SURPLUS-C02.
    function test_givenBurnCallback_whenRejectionPropagates_reverts() public {
        ohm.mint(address(inventory), 10);
        bytes32 beforeState = _accountingState();
        _armWithdrawal(ohm.burnFrom.selector, true);
        _expectPropagatedRejection();
        vm.prank(admin);
        inventory.burnSurplus();
        assertEq(_accountingState(), beforeState, "Mandatory operation completely rolls back");
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant)
