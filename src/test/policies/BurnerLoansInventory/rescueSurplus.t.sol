// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast)

// Interfaces

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";

contract BurnerLoansInventoryRescueSurplusTest is BurnerLoansInventoryTest {
    // Scenarios: BLINV-RESCUE-SURPLUS-L05.
    function test_givenInactive_whenUnauthorizedAndInvalid_reverts(bool enabled_) public {
        if (!enabled_) _disableInventory();
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(inventory));
        bytes32 state = _accountingState();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(inventory)
            )
        );
        vm.prank(outsider);
        inventory.rescueSurplus();
        assertEq(_accountingState(), state, "Inactivity rejects before unauthorized no-op");
    }

    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-N02, BLINV-RESCUE-SURPLUS-N03.
    function test_givenIdle_whenSurplusRescued(uint256 surplus_) public {
        _supply(50e9);
        surplus_ = bound(surplus_, 1, type(uint256).max - 50e9);
        ohm.mint(address(inventory), surplus_);
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.SurplusRescued(surplus_);
        vm.prank(admin);
        inventory.rescueSurplus();
        assertEq(ohm.balanceOf(address(trsry)), surplus_, "Entire surplus reaches Treasury");
        assertEq(ohm.balanceOf(address(inventory)), 50e9, "Only backing remains");
        assertEq(inventory.providerClaimOhm(provider), 50e9, "Provider claim unchanged");
        assertEq(inventory.suppliedIdleOhm(), 50e9, "Idle accounting unchanged");
    }

    function _assertRescueNoOp() internal {
        bytes32 beforeState = _accountingState();
        assertEq(inventory.surplusOhm(), 0, "Deficit cannot underflow surplus");
        vm.mockCallRevert(
            address(ohm),
            abi.encodeWithSelector(ohm.transfer.selector),
            hex"deadbeef"
        );
        vm.recordLogs();
        vm.prank(admin);
        inventory.rescueSurplus();
        assertEq(vm.getRecordedLogs().length, 0, "No rescue event");
        assertEq(_accountingState(), beforeState, "No transfer call or accounting change");
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-D01.
    function test_givenEmptyInventory_whenRescued_noOp() public {
        _assertRescueNoOp();
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-D01.
    function test_givenFullyBackedIdle_whenRescued_noOp() public {
        _supply(50e9);
        _assertRescueNoOp();
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-N01.
    function test_givenLostBacking_whenRescued_noOp() public {
        _supply(50e9);
        vm.prank(address(inventory));
        ohm.burn(1);
        _assertRescueNoOp();
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-P01.
    function test_givenTreasuryUpgrade_whenSurplusRescued() public {
        _supply(50e9);
        ohm.mint(address(inventory), 1);
        OlympusTreasury replacement = new OlympusTreasury(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.prank(admin);
        inventory.rescueSurplus();
        assertEq(ohm.balanceOf(address(trsry)), 0, "Old Treasury not paid");
        assertEq(ohm.balanceOf(address(replacement)), 1, "Current Treasury paid");
        assertEq(inventory.suppliedIdleOhm(), 50e9, "Provider backing preserved");
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-L04.
    function test_givenReEnabledInventory_whenSurplusRescued() public {
        _supply(50e9);
        ohm.mint(address(inventory), 1);
        _disableInventory();
        vm.prank(admin);
        inventory.reEnable();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.SurplusRescued(1);
        vm.prank(admin);
        inventory.rescueSurplus();
        assertEq(ohm.balanceOf(address(trsry)), 1, "Recovered after re-enable");
        assertEq(inventory.suppliedIdleOhm(), 50e9, "Provider idle untouched");
    }

    // Scenarios: BLINV-RESCUE-SURPLUS-D01, BLINV-RESCUE-SURPLUS-N01, BLINV-RESCUE-SURPLUS-N02, BLINV-RESCUE-SURPLUS-N03.
    function test_whenRescueBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenIdle_whenSurplusRescued(1);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore minimum rescue seed");
        snapshot = vm.snapshotState();
        test_givenIdle_whenSurplusRescued(type(uint256).max - 50e9);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore maximum rescue seed");
        test_givenEmptyInventory_whenRescued_noOp();
        test_givenLostBacking_whenRescued_noOp();
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast)
