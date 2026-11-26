// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

// Interfaces

// Libraries

// Contracts

import {BurnerLoansInventoryCallbackTest} from "./fixtures/BurnerLoansInventoryCallbackTest.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.

contract BurnerLoansInventoryWithdrawCallbackTest is BurnerLoansInventoryCallbackTest {
    // Scenarios: BLINV-WITHDRAW-C01.
    function test_givenWithdrawCallback_whenRejectionCaught_succeeds() public {
        _armWithdrawal(ohm.transfer.selector, false);

        vm.prank(provider);
        inventory.withdraw(10, recipient);
        assertEq(inventory.providerClaimOhm(provider), 90, "Claim debited once");
        assertEq(ohm.balanceOf(recipient), 10, "Recipient paid once");
        _assertNestedRejected();
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-WITHDRAW-C02.
    function test_givenWithdrawCallback_whenRejectionPropagates_reverts() public {
        bytes32 beforeState = _accountingState();
        _armWithdrawal(ohm.transfer.selector, true);
        _expectPropagatedRejection();
        vm.prank(provider);
        inventory.withdraw(10, recipient);
        assertEq(_accountingState(), beforeState, "Mandatory operation completely rolls back");
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
