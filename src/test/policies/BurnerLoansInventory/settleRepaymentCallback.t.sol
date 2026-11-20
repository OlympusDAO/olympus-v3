// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

// Interfaces

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Contracts
import {BurnerLoansInventoryCallbackTest} from "./fixtures/BurnerLoansInventoryCallbackTest.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.

contract BurnerLoansInventorySettleRepaymentCallbackTest is BurnerLoansInventoryCallbackTest {
    // Scenarios: BLINV-REPAYMENT-C01.
    function test_givenRepaymentBurnCallback_whenRejectionCaught_burns() public {
        _draw(200);
        _transferRepayment(200);
        uint256 supplyBefore = ohm.totalSupply();
        _armWithdrawal(ohm.burnFrom.selector, false);
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.RepaymentSettled(200, 107, 93);
        vm.prank(address(facility));
        inventory.settleRepayment(200);
        assertEq(inventory.activePrincipalOhm(), 0, "Principal repaid once");
        assertEq(inventory.suppliedIdleOhm(), 107, "Claims replenished");
        assertEq(inventory.surplusOhm(), 0, "Exact failed burn surplus");
        assertEq(ohm.totalSupply(), supplyBefore - 93, "Actual supply change");
        assertEq(
            mintr.mintApproval(address(inventory)),
            893,
            "Only successful burns restore approval"
        );
        _assertNestedRejected();
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-REPAYMENT-C02.
    function test_givenRepaymentBurnCallback_whenRejectionPropagates_defersBurn() public {
        _draw(200);
        _transferRepayment(200);
        uint256 supplyBefore = ohm.totalSupply();
        _armWithdrawal(ohm.burnFrom.selector, true);
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.OhmBurnFailed(
            93,
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)
        );
        vm.prank(address(facility));
        inventory.settleRepayment(200);
        assertEq(inventory.activePrincipalOhm(), 0, "Principal repaid once");
        assertEq(inventory.suppliedIdleOhm(), 107, "Claims replenished");
        assertEq(inventory.surplusOhm(), 93, "Exact failed burn surplus");
        assertEq(ohm.totalSupply(), supplyBefore, "Actual supply change");
        assertEq(
            mintr.mintApproval(address(inventory)),
            800,
            "Only successful burns restore approval"
        );
        assertEq(inventory.providerClaimOhm(address(_token)), 7, "Nested claim unchanged");
        _assertInventoryInvariant();
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
