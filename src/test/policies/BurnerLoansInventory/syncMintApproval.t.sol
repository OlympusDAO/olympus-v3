// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Libraries
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.

contract BurnerLoansInventorySyncMintApprovalTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
    }

    // Scenarios: BLINV-MINT-APPROVAL-L02.
    function test_givenConservativeDeficit_restoresDesiredApproval(uint128 deficit_) public {
        deficit_ = uint128(bound(deficit_, 1, DEFAULT_CAP));
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), deficit_);
        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();
        assertEq(approval, DEFAULT_CAP, "returned approval");
        _assertInventoryInvariant();
    }

    function test_givenApprovalEqualToDesired_isIdempotent() public {
        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.MintApprovalSynchronized(DEFAULT_CAP);
        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();

        assertEq(approval, DEFAULT_CAP, "returned approval");
        _assertInventoryInvariant();
    }

    function test_givenExternalOverApproval_reducesToDesired(uint128 excess_) public {
        excess_ = uint128(bound(excess_, 1, type(uint128).max - DEFAULT_CAP));
        vm.prank(address(inventory));
        mintr.increaseMintApproval(address(inventory), excess_);

        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();

        assertEq(approval, DEFAULT_CAP, "returned approval");
        _assertInventoryInvariant();
    }

    function test_givenApprovalDeficit_restoresDeficit() public {
        _draw(100e9);
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), 40e9);
        vm.prank(address(facility));
        inventory.settleDefault(40e9);
        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();

        assertEq(approval, inventory.desiredMintApproval(), "approval synchronized");
        _assertInventoryInvariant();
    }

    function test_givenGloballyDisabled_reverts(uint128 deficit_) public {
        deficit_ = uint128(bound(deficit_, 1, DEFAULT_CAP));
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), deficit_);
        _disableInventory();

        uint256 approvalBefore = mintr.mintApproval(address(inventory));

        _expectNotEnabled();
        vm.prank(burnerLoansAdmin);
        inventory.syncMintApproval();

        assertEq(mintr.mintApproval(address(inventory)), approvalBefore, "approval unchanged");
    }

    // Scenarios: BLINV-MINT-APPROVAL-A01.
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != burnerLoansAdmin);
        _expectRole(BURNER_LOANS_ADMIN_ROLE);
        vm.prank(caller_);
        inventory.syncMintApproval();
    }

    function test_givenSuppliedOhm_synchronizesToReducedDesiredApproval(uint128 supplied_) public {
        supplied_ = uint128(bound(supplied_, 1, DEFAULT_CAP));
        _supply(supplied_);
        vm.prank(address(inventory));
        mintr.increaseMintApproval(address(inventory), supplied_);

        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();

        assertEq(approval, DEFAULT_CAP - supplied_, "supplied-adjusted approval");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-MINT-APPROVAL-P03.
    function test_givenInactiveEnabledInventory_whenAction_reverts() public {
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(burnerLoansAdmin);
        inventory.syncMintApproval();
        assertEq(_accountingState(), beforeState, "Inactive call preserves accounting");
        _reactivateInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.MintApprovalSynchronized(DEFAULT_CAP);
        vm.prank(burnerLoansAdmin);
        inventory.syncMintApproval();
        assertEq(mintr.mintApproval(address(inventory)), DEFAULT_CAP, "Approval synchronized");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-L01, BLINV-DRAW-L01, BLINV-MINT-APPROVAL-L01, BLINV-REPAYMENT-L01, BLINV-DEFAULT-L01, BLINV-WITHDRAW-L01.
    function test_givenPausedInventory_whenAction_reverts() public {
        _disableInventory();
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(burnerLoansAdmin);
        inventory.syncMintApproval();
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-SUPPLY-L04, BLINV-DRAW-L03, BLINV-MINT-APPROVAL-L03, BLINV-REPAYMENT-L03, BLINV-DEFAULT-L03, BLINV-WITHDRAW-L03.
    function test_givenInactiveDisabledInventory_whenAction_reverts() public {
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(burnerLoansAdmin);
        inventory.syncMintApproval();
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-MINT-APPROVAL-L04.
    function test_givenReEnabledInventory_whenAction_succeeds() public {
        _disableInventory();
        _reEnableInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.MintApprovalSynchronized(DEFAULT_CAP);
        vm.prank(burnerLoansAdmin);
        inventory.syncMintApproval();
        assertEq(mintr.mintApproval(address(inventory)), DEFAULT_CAP, "Approval synchronized");
        _assertInventoryInvariant();
    }

    function _syncAndAssert(uint128 desired_, uint256 actual_) internal {
        vm.prank(admin);
        inventory.setGlobalDebtCap(desired_);
        uint256 current = mintr.mintApproval(address(inventory));
        vm.prank(address(inventory));
        if (actual_ >= current) mintr.increaseMintApproval(address(inventory), actual_ - current);
        else mintr.decreaseMintApproval(address(inventory), current - actual_);
        if (actual_ < desired_)
            vm.expectCall(
                address(mintr),
                abi.encodeWithSelector(
                    MINTRv1.increaseMintApproval.selector,
                    address(inventory),
                    uint256(desired_) - actual_
                )
            );
        else if (actual_ > desired_)
            vm.expectCall(
                address(mintr),
                abi.encodeWithSelector(
                    MINTRv1.decreaseMintApproval.selector,
                    address(inventory),
                    actual_ - desired_
                )
            );
        else {
            vm.mockCallRevert(
                address(mintr),
                abi.encodeWithSelector(MINTRv1.increaseMintApproval.selector),
                hex"deadbeef"
            );
            vm.mockCallRevert(
                address(mintr),
                abi.encodeWithSelector(MINTRv1.decreaseMintApproval.selector),
                hex"deadbeef"
            );
        }
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.MintApprovalSynchronized(desired_);
        vm.prank(burnerLoansAdmin);
        uint256 actual = inventory.syncMintApproval();
        assertEq(actual, desired_, "Exact returned approval");
        assertEq(mintr.mintApproval(address(inventory)), desired_, "Exact stored approval");
        assertEq(ohm.totalSupply(), 0, "Approval does not mint OHM");
        assertEq(inventory.activePrincipalOhm(), 0, "No principal change");
        vm.clearMockedCalls();
    }

    // Scenarios: BLINV-MINT-APPROVAL-N01, BLINV-MINT-APPROVAL-N02, BLINV-MINT-APPROVAL-N03, BLINV-MINT-APPROVAL-N04, BLINV-MINT-APPROVAL-N05, BLINV-MINT-APPROVAL-N06, BLINV-MINT-APPROVAL-N07, BLINV-MINT-APPROVAL-N08.
    function test_whenApprovalBoundarySeeds() public {
        _syncAndAssert(100e9, 0);
        _syncAndAssert(100e9, 100e9 - 1);
        _syncAndAssert(100e9, 100e9);
        _syncAndAssert(100e9, 100e9 + 1);
        _syncAndAssert(100e9, type(uint256).max);
        _syncAndAssert(0, 0);
        _syncAndAssert(0, 1);
        _syncAndAssert(type(uint128).max, 0);
    }

    function _givenApprovalRestorationFailure() internal {
        _draw(100);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeWithSelector(MINTRv1.increaseMintApproval.selector),
            abi.encodeWithSelector(ApprovalChangeFailed.selector)
        );
        vm.prank(address(facility));
        inventory.settleDefault(100);
        assertEq(
            mintr.mintApproval(address(inventory)),
            DEFAULT_CAP - 100,
            "Caught restoration leaves actual deficit"
        );
    }

    // Scenarios: BLINV-MINT-APPROVAL-P02.
    function test_givenCaughtRestorationFailure_whenSyncFails_reverts() public {
        _givenApprovalRestorationFailure();
        bytes32 beforeState = _accountingState();
        vm.expectRevert(ApprovalChangeFailed.selector);
        vm.prank(burnerLoansAdmin);
        inventory.syncMintApproval();
        assertEq(_accountingState(), beforeState, "Failed strict reconciliation preserves deficit");
    }

    // Scenarios: BLINV-MINT-APPROVAL-P01.
    function test_givenCaughtRestorationFailure_whenSyncRetried_succeeds() public {
        _givenApprovalRestorationFailure();
        vm.clearMockedCalls();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.MintApprovalSynchronized(DEFAULT_CAP);
        vm.prank(burnerLoansAdmin);
        uint256 approval = inventory.syncMintApproval();
        assertEq(approval, DEFAULT_CAP, "Retry restores exact capacity");
        assertEq(ohm.balanceOf(recipient), 100, "No new token movement");
        _assertInventoryInvariant();
    }

    error ApprovalChangeFailed();

    // Scenarios: BLINV-MINT-APPROVAL-L01, BLINV-MINT-APPROVAL-L03.
    function test_whenActionLifecycleSeeds() public {
        {
            uint256 activeSnapshot = vm.snapshotState();
            test_givenPausedInventory_whenAction_reverts();
            assertTrue(vm.revertToStateAndDelete(activeSnapshot), "Restore paused action seed");
        }
        {
            uint256 inactiveSnapshot = vm.snapshotState();
            test_givenInactiveDisabledInventory_whenAction_reverts();
            assertTrue(vm.revertToStateAndDelete(inactiveSnapshot), "Restore paused action seed");
        }
        uint256 snapshot = vm.snapshotState();
        test_givenInactiveEnabledInventory_whenAction_reverts();
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore reactivation seed");
        test_givenReEnabledInventory_whenAction_succeeds();
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
