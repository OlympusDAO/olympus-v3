// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant)

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Libraries

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

contract BurnerLoansInventoryBurnSurplusTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
    }

    // Scenarios: BLINV-BURN-SURPLUS-P03.
    function test_givenCoreBusy_whenUnauthorizedBurnsEmptySurplus_reverts(
        bool active_,
        bool enabled_
    ) public {
        if (!enabled_) _disableInventory();
        if (!active_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(inventory));
        }
        bytes memory reason = abi.encodeWithSelector(
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector
        );
        vm.mockCallRevert(
            address(facility),
            abi.encodeCall(IBurnerLoansCore.requireNotReentrant, ()),
            reason
        );
        bytes32 beforeState = _accountingState();
        vm.expectRevert(reason);
        vm.prank(outsider);
        inventory.burnSurplus();
        assertEq(_accountingState(), beforeState, "Rejected burn preserves accounting");
    }

    function test_givenSurplus_burnsFullAmount(uint256 amount_) public {
        amount_ = bound(amount_, 1, type(uint256).max - ohm.totalSupply());
        ohm.mint(address(inventory), amount_);
        uint256 supplyBefore = ohm.totalSupply();

        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.SurplusBurned(amount_);
        vm.prank(admin);
        inventory.burnSurplus();

        assertEq(inventory.surplusOhm(), 0, "surplus burned");
        assertEq(ohm.totalSupply(), supplyBefore - amount_, "total supply reduced");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-BURN-SURPLUS-D02.
    function test_givenBurnFailure_revertsAndPreservesSurplus(uint256 amount_) public {
        amount_ = bound(amount_, 1, type(uint256).max - ohm.totalSupply());
        ohm.mint(address(inventory), amount_);
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.burnOhm, (address(inventory), amount_)),
            failure
        );

        vm.expectRevert(failure);
        vm.prank(admin);
        inventory.burnSurplus();

        assertEq(inventory.surplusOhm(), amount_, "surplus preserved");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-BURN-SURPLUS-A01.
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != address(config));
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.burnSurplus();
    }

    // Scenarios: BLINV-BURN-SURPLUS-L01.
    function test_givenGloballyDisabled_reverts(uint256 amount_) public {
        amount_ = bound(amount_, 1, type(uint256).max - ohm.totalSupply());
        ohm.mint(address(inventory), amount_);
        _disableInventory();

        _expectNotEnabled();
        vm.prank(admin);
        inventory.burnSurplus();

        assertEq(inventory.surplusOhm(), amount_, "surplus unchanged");
    }

    // Scenarios: BLINV-BURN-SURPLUS-L02, BLINV-BURN-SURPLUS-N02, BLINV-BURN-SURPLUS-N03, BLINV-BURN-SURPLUS-N04.
    function test_givenIdle_whenSurplusBurned(uint256 surplus_) public {
        _supply(50e9);
        surplus_ = bound(surplus_, 1, type(uint256).max - 50e9);
        ohm.mint(address(inventory), surplus_);
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.SurplusBurned(surplus_);
        vm.prank(admin);
        inventory.burnSurplus();
        assertEq(ohm.balanceOf(address(inventory)), 50e9, "Only provider backing remains");
        assertEq(ohm.totalSupply(), 50e9, "Only true surplus burned");
        assertEq(inventory.providerClaimOhm(provider), 50e9, "Claim unchanged");
        assertEq(inventory.suppliedIdleOhm(), 50e9, "Idle accounting unchanged");
        assertEq(inventory.activePrincipalOhm(), 0, "Principal unchanged");
    }

    function _assertBurnNoOp() internal {
        bytes32 beforeState = _accountingState();
        assertEq(inventory.surplusOhm(), 0, "Deficit cannot underflow surplus");
        vm.mockCallRevert(
            address(mintr),
            abi.encodeWithSelector(MINTRv1.burnOhm.selector),
            hex"deadbeef"
        );
        vm.recordLogs();
        vm.prank(admin);
        inventory.burnSurplus();
        assertEq(vm.getRecordedLogs().length, 0, "No burn event");
        assertEq(_accountingState(), beforeState, "No burn call or accounting change");
    }

    // Scenarios: BLINV-BURN-SURPLUS-D01.
    function test_givenEmptyInventory_whenBurned_noOp() public {
        _assertBurnNoOp();
    }

    // Scenarios: BLINV-BURN-SURPLUS-D01.
    function test_givenFullyBackedIdle_whenBurned_noOp() public {
        _supply(50e9);
        _assertBurnNoOp();
    }

    // Scenarios: BLINV-BURN-SURPLUS-N01.
    function test_givenLostBacking_whenBurned_noOp() public {
        _supply(50e9);
        vm.prank(address(inventory));
        ohm.burn(1);
        _assertBurnNoOp();
    }

    function _givenIdleAndSurplus() internal {
        _supply(50e9);
        ohm.mint(address(inventory), 1);
    }

    // Scenarios: BLINV-BURN-SURPLUS-P01.
    function test_givenInactiveEnabledInventory_whenBurned_reverts() public {
        _givenIdleAndSurplus();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(admin);
        inventory.burnSurplus();
        assertEq(_accountingState(), beforeState, "Inactive recovery preserves funding");
        _reactivateInventory();
        vm.prank(admin);
        inventory.burnSurplus();
        assertEq(ohm.balanceOf(address(inventory)), 50e9, "Recovery after reactivation");
    }

    // Scenarios: BLINV-BURN-SURPLUS-L03.
    function test_givenInactiveDisabledInventory_whenBurned_reverts() public {
        _givenIdleAndSurplus();
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(admin);
        inventory.burnSurplus();
        assertEq(
            _accountingState(),
            beforeState,
            "Own activity precedes pause and preserves funding"
        );
        _reactivateInventory();
        _reEnableInventory();
        vm.prank(admin);
        inventory.burnSurplus();
        assertEq(
            ohm.balanceOf(address(inventory)),
            50e9,
            "Recovery after reactivation and re-enable"
        );
    }

    // Scenarios: BLINV-BURN-SURPLUS-L04.
    function test_givenReEnabledInventory_whenBurned() public {
        _supply(50e9);
        ohm.mint(address(inventory), 1);
        _disableInventory();
        vm.prank(admin);
        inventory.reEnable();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.SurplusBurned(1);
        vm.prank(admin);
        inventory.burnSurplus();
        assertEq(ohm.balanceOf(address(inventory)), 50e9, "Only surplus burned after re-enable");
    }

    // Scenarios: BLINV-BURN-SURPLUS-A03.
    function test_givenReplacedConfiguratorAndNoSurplus_whenBurned_reverts() public {
        vm.prank(admin);
        inventory.setConfigOperator(outsider);
        bytes32 beforeState = _accountingState();
        _expectNotAuthorised();
        vm.prank(address(config));
        inventory.burnSurplus();
        assertEq(_accountingState(), beforeState, "Authorization precedes empty-surplus return");
    }

    // Scenarios: BLINV-BURN-SURPLUS-D01, BLINV-BURN-SURPLUS-N01, BLINV-BURN-SURPLUS-N02, BLINV-BURN-SURPLUS-N03, BLINV-BURN-SURPLUS-N04.
    function test_whenBurnBoundarySeeds() public {
        uint256[3] memory amounts = [uint256(1), 2, type(uint256).max - 50e9];
        for (uint256 i; i < amounts.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            test_givenIdle_whenSurplusBurned(amounts[i]);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore burn seed");
        }
        test_givenEmptyInventory_whenBurned_noOp();
        test_givenLostBacking_whenBurned_noOp();
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant)
