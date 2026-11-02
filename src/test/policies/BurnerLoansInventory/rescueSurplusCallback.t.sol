// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast)

// Interfaces

// Libraries

// Contracts

import {BurnerLoansInventoryCallbackTest} from "./fixtures/BurnerLoansInventoryCallbackTest.sol";

contract BurnerLoansInventoryRescueSurplusCallbackTest is BurnerLoansInventoryCallbackTest {
    // Scenarios: BLINV-RESCUE-SURPLUS-C01.
    function test_givenRescueCallback_whenRejectionCaught_succeeds() public {
        ohm.mint(address(inventory), 10);
        _armWithdrawal(ohm.transfer.selector, false);

        vm.prank(admin);
        inventory.rescueSurplus();
        assertEq(ohm.balanceOf(address(trsry)), 10, "Surplus transferred once");
        assertEq(inventory.suppliedIdleOhm(), 107, "Provider backing preserved");
        _assertNestedRejected();
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-C02.
    function test_givenRescueCallback_whenRejectionPropagates_reverts() public {
        ohm.mint(address(inventory), 10);
        bytes32 beforeState = _accountingState();
        _armWithdrawal(ohm.transfer.selector, true);
        _expectPropagatedRejection();
        vm.prank(admin);
        inventory.rescueSurplus();
        assertEq(_accountingState(), beforeState, "Mandatory operation completely rolls back");
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast)
