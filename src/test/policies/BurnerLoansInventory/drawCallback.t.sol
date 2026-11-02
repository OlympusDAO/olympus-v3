// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces

// Contracts
import {BurnerLoansInventoryCallbackTest} from "./fixtures/BurnerLoansInventoryCallbackTest.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.

contract BurnerLoansInventoryDrawCallbackTest is BurnerLoansInventoryCallbackTest {
    // Scenarios: BLINV-DRAW-C01.
    function test_givenDrawMintCallback_whenRejectionCaught_succeeds() public {
        _armSupply(ohm.mint.selector, false);

        vm.prank(address(facility));
        inventory.draw(recipient, 200);
        assertEq(inventory.activePrincipalOhm(), 200, "Draw counted once");
        assertEq(ohm.balanceOf(recipient), 200, "Recipient paid once");
        assertEq(inventory.suppliedIdleOhm(), 0, "Idle used first");
        assertEq(mintr.mintApproval(address(inventory)), 800, "Mint consumes shortfall approval");
        _assertNestedRejected();
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-DRAW-C02.
    function test_givenDrawMintCallback_whenRejectionPropagates_reverts() public {
        bytes32 beforeState = _accountingState();
        _armSupply(ohm.mint.selector, true);
        _expectPropagatedRejection();
        vm.prank(address(facility));
        inventory.draw(recipient, 200);
        assertEq(_accountingState(), beforeState, "Mandatory operation completely rolls back");
    }

    // Scenarios: BLINV-DRAW-C01.
    function test_givenDrawTransferCallback_whenRejectionCaught_succeeds() public {
        _armSupply(ohm.transfer.selector, false);

        vm.prank(address(facility));
        inventory.draw(recipient, 200);
        assertEq(inventory.activePrincipalOhm(), 200, "Draw counted once");
        assertEq(ohm.balanceOf(recipient), 200, "Recipient paid once");
        assertEq(inventory.suppliedIdleOhm(), 0, "Idle used first");
        _assertNestedRejected();
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-DRAW-C02.
    function test_givenDrawTransferCallback_whenRejectionPropagates_reverts() public {
        bytes32 beforeState = _accountingState();
        _armSupply(ohm.transfer.selector, true);
        _expectPropagatedRejection();
        vm.prank(address(facility));
        inventory.draw(recipient, 200);
        assertEq(_accountingState(), beforeState, "Mandatory operation completely rolls back");
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
