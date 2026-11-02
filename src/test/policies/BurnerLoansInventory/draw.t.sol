// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Contracts

import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {BurnerLoansInventoryTest} from "src/test/policies/BurnerLoansInventory/BurnerLoansInventoryTest.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.

contract BurnerLoansInventoryDrawTest is BurnerLoansInventoryTest {
    error TransferFailed();

    uint128 internal constant DRAW_CAP = 1_000e9;
    uint128 internal constant SUPPLIED_IDLE = 300e9;

    event OhmDrawn(
        address indexed recipient,
        uint256 amount,
        uint256 suppliedAmount,
        uint256 mintedAmount
    );

    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DRAW_CAP);
    }

    // Scenarios: BLINV-DRAW-L02, BLINV-DRAW-N04.
    function test_givenMixedFunding_drawsExactAmount(uint128 amount_) public {
        amount_ = uint128(bound(amount_, SUPPLIED_IDLE + 1, DRAW_CAP));
        uint128 mintedAmount = amount_ - SUPPLIED_IDLE;
        _supply(SUPPLIED_IDLE);

        vm.expectEmit(true, true, true, true, address(inventory));
        emit OhmDrawn(recipient, amount_, SUPPLIED_IDLE, mintedAmount);
        vm.prank(address(facility));
        inventory.draw(recipient, amount_);

        _assertInventoryState(recipient, amount_, amount_, SUPPLIED_IDLE, 0, DRAW_CAP - amount_);
    }

    // Scenarios: BLINV-DRAW-N04.
    function test_givenMintFunding_drawsExactAmount(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, DRAW_CAP));
        vm.prank(address(facility));
        inventory.draw(recipient, amount_);

        _assertInventoryState(recipient, amount_, amount_, 0, 0, DRAW_CAP - amount_);
    }

    // Scenarios: BLINV-DRAW-N04.
    function test_givenIdleFunding_drawsExactAmount(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, SUPPLIED_IDLE));
        _supply(SUPPLIED_IDLE);

        vm.prank(address(facility));
        inventory.draw(recipient, amount_);

        _assertInventoryState(
            recipient,
            amount_,
            amount_,
            SUPPLIED_IDLE,
            SUPPLIED_IDLE - amount_,
            DRAW_CAP - SUPPLIED_IDLE
        );
    }

    // Scenarios: BLINV-DRAW-D01.
    function test_givenMintFailure_revertsAndRollsBack() public {
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.mintOhm, (address(inventory), 100e9)),
            failure
        );

        vm.expectRevert(failure);
        vm.prank(address(facility));
        inventory.draw(recipient, 100e9);

        assertEq(inventory.activePrincipalOhm(), 0, "active principal rolled back");
        assertEq(ohm.balanceOf(address(inventory)), 0, "BLI balance rolled back");
        assertEq(ohm.balanceOf(recipient), 0, "recipient unchanged");
        assertEq(mintr.mintApproval(address(inventory)), 1_000e9, "approval rolled back");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-DRAW-D02.
    function test_givenTransferFailure_revertsAndRollsBack() public {
        bytes memory failure = abi.encodeWithSelector(TransferFailed.selector);
        vm.mockCallRevert(
            address(ohm),
            abi.encodeWithSelector(ERC20.transfer.selector, recipient, 100e9),
            failure
        );

        vm.expectRevert(failure);
        vm.prank(address(facility));
        inventory.draw(recipient, 100e9);

        assertEq(inventory.activePrincipalOhm(), 0, "active principal rolled back");
        assertEq(ohm.balanceOf(address(inventory)), 0, "BLI balance rolled back");
        assertEq(ohm.balanceOf(recipient), 0, "recipient unchanged");
        assertEq(mintr.mintApproval(address(inventory)), 1_000e9, "approval rolled back");
        _assertInventoryInvariant();
    }

    function test_givenExactCapacity_succeeds() public {
        uint128 capacity = uint128(inventory.availableCapacity());

        vm.prank(address(facility));
        inventory.draw(recipient, capacity);

        assertEq(inventory.availableCapacity(), 0, "capacity exhausted");
        assertEq(ohm.balanceOf(recipient), capacity, "recipient balance");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-DRAW-N05.
    function test_givenMaximumExternalOverApproval_drawRemainsCapBounded() public {
        _supply(1e9);
        vm.prank(address(inventory));
        mintr.increaseMintApproval(address(inventory), type(uint256).max);

        assertEq(inventory.availableCapacity(), 1_000e9, "capacity remains bounded by cap");

        vm.prank(address(facility));
        inventory.draw(recipient, 1_000e9);

        assertEq(ohm.balanceOf(recipient), 1_000e9, "recipient receives cap");
        assertEq(inventory.activePrincipalOhm(), 1_000e9, "active principal reaches cap");
        assertEq(inventory.availableCapacity(), 0, "capacity exhausted at cap");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity.selector,
                1,
                0
            )
        );
        vm.prank(address(facility));
        inventory.draw(recipient, 1);

        vm.prank(burnerLoansAdmin);
        inventory.syncMintApproval();
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-DRAW-N03.
    function test_givenAmountAboveCapacity_reverts(uint128 amount_) public {
        uint256 capacity = inventory.availableCapacity();
        amount_ = uint128(bound(amount_, capacity + 1, type(uint128).max));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity.selector,
                amount_,
                capacity
            )
        );
        vm.prank(address(facility));
        inventory.draw(recipient, amount_);

        assertEq(inventory.activePrincipalOhm(), 0, "active principal unchanged");
        assertEq(ohm.balanceOf(recipient), 0, "recipient unchanged");
        _assertInventoryInvariant();
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != address(facility));
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.draw(recipient, 1);
    }

    // Scenarios: BLINV-DRAW-N01.
    function test_givenZeroAmount_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAmount.selector);
        vm.prank(address(facility));
        inventory.draw(recipient, 0);

        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-DRAW-N02.
    function test_givenZeroRecipient_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAddress.selector);
        vm.prank(address(facility));
        inventory.draw(address(0), 1);

        _assertInventoryInvariant();
    }

    function test_givenGloballyDisabled_reverts() public {
        _disableInventory();

        _expectNotEnabled();
        vm.prank(address(facility));
        inventory.draw(recipient, 1);
    }

    function test_givenActiveSameKernelNonFacility_reverts() public {
        _expectNotAuthorised();
        vm.prank(address(config));
        inventory.draw(recipient, 1);
    }

    // Scenarios: BLINV-DRAW-P01.
    function test_givenInactiveEnabledInventory_whenAction_reverts() public {
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(address(facility));
        inventory.draw(recipient, 1);
        assertEq(_accountingState(), beforeState, "Inactive call preserves accounting");
        _reactivateInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.OhmDrawn(recipient, 1, 0, 1);
        vm.prank(address(facility));
        inventory.draw(recipient, 1);
        assertEq(inventory.activePrincipalOhm(), 1, "Principal drawn once");
        assertEq(ohm.balanceOf(recipient), 1, "Recipient paid");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-L01, BLINV-DRAW-L01, BLINV-MINT-APPROVAL-L01, BLINV-REPAYMENT-L01, BLINV-DEFAULT-L01, BLINV-WITHDRAW-L01.
    function test_givenPausedInventory_whenAction_reverts() public {
        _disableInventory();
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(address(facility));
        inventory.draw(recipient, 1);
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-SUPPLY-L04, BLINV-DRAW-L03, BLINV-MINT-APPROVAL-L03, BLINV-REPAYMENT-L03, BLINV-DEFAULT-L03, BLINV-WITHDRAW-L03.
    function test_givenInactiveDisabledInventory_whenAction_reverts() public {
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(address(facility));
        inventory.draw(recipient, 1);
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-DRAW-L04.
    function test_givenReEnabledInventory_whenAction_succeeds() public {
        _disableInventory();
        _reEnableInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.OhmDrawn(recipient, 1, 0, 1);
        vm.prank(address(facility));
        inventory.draw(recipient, 1);
        assertEq(inventory.activePrincipalOhm(), 1, "Principal drawn once");
        assertEq(ohm.balanceOf(recipient), 1, "Recipient paid");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-L02, BLINV-DRAW-L01, BLINV-REPAYMENT-L01, BLINV-DEFAULT-L01, BLINV-WITHDRAW-L01.
    function test_givenPausedInventory_whenZeroAmount_reverts() public {
        _disableInventory();
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(address(facility));
        inventory.draw(recipient, 0);
        assertEq(_accountingState(), beforeState, "Pause precedes zero input");
    }

    // Scenarios: BLINV-DRAW-L03.
    function test_givenInactiveDisabledInventory_whenZeroAmount_reverts() public {
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(address(facility));
        inventory.draw(recipient, 0);
        assertEq(_accountingState(), beforeState, "Pause precedes zero input");
    }

    // Scenarios: BLINV-DRAW-A01.
    function test_whenUnauthorizedCallerWithZeroOrOne_reverts(address caller_) public {
        vm.assume(caller_ != address(facility));
        bytes32 beforeState = _accountingState();
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.draw(recipient, 0);
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.draw(recipient, 1);
        assertEq(_accountingState(), beforeState, "Unauthorized calls preserve accounting");
    }

    // Scenarios: BLINV-DRAW-N04.
    function test_givenMaximumCap_whenDrawn(
        uint128 amount_,
        uint128 idle_,
        bool selfRecipient_
    ) public {
        _enableAndSetCap(type(uint128).max);
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        if (idle_ != 0) _supply(idle_);
        uint128 supplied = idle_;
        uint128 used = amount_ < supplied ? amount_ : supplied;
        uint128 minted = amount_ - used;
        address target = selfRecipient_ ? address(inventory) : provider;
        uint256 supplyBefore = ohm.totalSupply();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.OhmDrawn(target, amount_, used, minted);
        vm.prank(address(facility));
        inventory.draw(target, amount_);
        assertEq(inventory.activePrincipalOhm(), amount_, "Exact principal");
        assertEq(inventory.suppliedIdleOhm(), supplied - used, "Idle consumed first");
        assertEq(inventory.providerClaimOhm(provider), supplied, "Claim unchanged");
        assertEq(ohm.totalSupply(), supplyBefore + minted, "Only shortfall minted");
        assertEq(
            ohm.balanceOf(target),
            selfRecipient_ ? uint256(supplied) + minted : amount_,
            "Actual recipient behavior"
        );
        assertEq(
            inventory.availableCapacity(),
            uint256(type(uint128).max) - amount_,
            "Remaining cap capacity"
        );
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-DRAW-N03, BLINV-DRAW-N04.
    function test_whenDrawBoundarySeeds() public {
        uint128[5] memory amounts = [
            uint128(1),
            SUPPLIED_IDLE - 1,
            SUPPLIED_IDLE,
            SUPPLIED_IDLE + 1,
            type(uint128).max
        ];
        for (uint256 i; i < amounts.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            test_givenMaximumCap_whenDrawn(amounts[i], SUPPLIED_IDLE, false);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore funding seed");
        }
        test_givenAmountAboveCapacity_reverts(DRAW_CAP + 1);
        test_givenAmountAboveCapacity_reverts(type(uint128).max);
    }

    // Scenarios: BLINV-DRAW-L01, BLINV-DRAW-L03.
    function test_whenActionLifecycleSeeds() public {
        {
            uint256 activeSnapshot = vm.snapshotState();
            test_givenPausedInventory_whenAction_reverts();
            assertTrue(vm.revertToStateAndDelete(activeSnapshot), "Restore paused action seed");
            activeSnapshot = vm.snapshotState();
            test_givenPausedInventory_whenZeroAmount_reverts();
            assertTrue(vm.revertToStateAndDelete(activeSnapshot), "Restore zero input seed");
        }
        {
            uint256 inactiveSnapshot = vm.snapshotState();
            test_givenInactiveDisabledInventory_whenAction_reverts();
            assertTrue(vm.revertToStateAndDelete(inactiveSnapshot), "Restore paused action seed");
            inactiveSnapshot = vm.snapshotState();
            test_givenInactiveDisabledInventory_whenZeroAmount_reverts();
            assertTrue(vm.revertToStateAndDelete(inactiveSnapshot), "Restore zero input seed");
        }
        uint256 snapshot = vm.snapshotState();
        test_givenInactiveEnabledInventory_whenAction_reverts();
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore reactivation seed");
        test_givenReEnabledInventory_whenAction_succeeds();
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
