// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(missing-zero-check,unsafe-typecast,unused-return)

import {BurnerLoansInventoryHandler} from "./fixtures/BurnerLoansInventoryHandler.sol";

// Interfaces

// Contracts
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {BurnerLoansInventoryTest} from "src/test/policies/BurnerLoansInventory/BurnerLoansInventoryTest.sol";

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.
// Test fixtures accept zero addresses to model unset, cleared, and invalid states.
// Scenario-specific contracts and fixtures have no cross-file consumers.

contract BurnerLoansInventoryInvariantTest is StdInvariant, BurnerLoansInventoryTest {
    BurnerLoansInventoryHandler internal handler;

    function setUp() public override {
        super.setUp();

        handler = new BurnerLoansInventoryHandler(
            inventory,
            ohm,
            admin,
            address(facility),
            provider,
            recipient
        );

        vm.startPrank(admin);
        inventory.setConfigOperator(address(config));
        inventory.enable("");
        vm.stopPrank();

        vm.prank(admin);
        inventory.setGlobalDebtCap(DEFAULT_CAP);

        // Seed the campaign with idle greater than the cap so every invariant run covers the
        // custody-is-not-debt boundary before randomized transitions begin.
        handler.supply(DEFAULT_CAP + 1);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.supply.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.draw.selector;
        selectors[3] = handler.settleRepayment.selector;
        selectors[4] = handler.settleDefault.selector;
        selectors[5] = handler.setGlobalDebtCap.selector;
        selectors[6] = handler.pauseAndRecover.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // given arbitrary funding/default/repayment/cap sequences and pause/recovery cycles for one provider
    //  when its aggregate accounting is inspected
    //   then the cap, approval, custody, claim, and capacity invariants hold
    function invariant_Accounting() public view {
        _assertInventoryInvariant();
        assertEq(
            inventory.activePrincipalOhm(),
            handler.modelPrincipal(),
            "Principal matches independent deltas"
        );
        assertEq(
            inventory.suppliedOhm(),
            handler.modelClaim(),
            "Aggregate claim matches independent deltas"
        );
        assertEq(
            inventory.providerClaimOhm(provider),
            handler.modelClaim(),
            "One-provider campaign claim sum"
        );
        assertEq(
            inventory.suppliedIdleOhm(),
            handler.modelIdle(),
            "Idle matches funding/repayment model"
        );
    }
}

// forge-lint: disable-end(missing-zero-check,unsafe-typecast,unused-return)
