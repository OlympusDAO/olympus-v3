// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces

// Libraries

import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";

// Contracts

import {BurnerLoansInventoryCallbackTest} from "./fixtures/BurnerLoansInventoryCallbackTest.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.

contract BurnerLoansInventorySupplyCallbackTest is BurnerLoansInventoryCallbackTest {
    // Scenarios: BLINV-SUPPLY-C01.
    function test_givenSupplyCallback_whenRejectionCaught_succeeds() public {
        _prepareSupply(10);
        _armWithdrawal(ohm.transferFrom.selector, false);

        vm.prank(provider);
        inventory.supply(10);
        assertEq(inventory.providerClaimOhm(provider), 110, "Provider credited once");
        assertEq(inventory.suppliedIdleOhm(), 117, "Exact receipt credited");
        _assertNestedRejected();
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-C02.
    function test_givenSupplyCallback_whenRejectionPropagates_reverts() public {
        _prepareSupply(10);
        bytes32 beforeState = _accountingState();
        _armWithdrawal(ohm.transferFrom.selector, true);
        _expectPropagatedRejection();
        vm.prank(provider);
        inventory.supply(10);
        assertEq(_accountingState(), beforeState, "Mandatory operation completely rolls back");
    }

    // Scenarios: BLINV-SUPPLY-D04.
    function test_givenOverDeliveredReceipt_whenSupplied_reverts() public {
        _prepareSupply(10);
        bytes32 beforeState = _accountingState();
        _token.setExtraReceipt(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(ohm),
                address(inventory),
                10,
                11
            )
        );
        vm.prank(provider);
        inventory.supply(10);
        assertEq(_accountingState(), beforeState, "Over-delivery creates no credit or supply");
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
