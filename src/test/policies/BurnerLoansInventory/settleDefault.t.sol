// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

// Interfaces

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.

contract BurnerLoansInventorySettleDefaultTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
        _supply(100e9);
        _draw(100e9);
    }

    // Scenarios: BLINV-DEFAULT-L02, BLINV-DEFAULT-N03.
    function test_givenPartialDefault_preservesClaim(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 100e9 - 1));
        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.PrincipalDefaulted(amount_);
        vm.prank(address(facility));
        inventory.settleDefault(amount_);
        assertEq(inventory.activePrincipalOhm(), 100e9 - amount_, "active principal");
        assertEq(inventory.suppliedOhm(), 100e9, "claim");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-DEFAULT-N03.
    function test_givenFullDefault_clearsPrincipalAndPreservesClaim() public {
        vm.prank(address(facility));
        inventory.settleDefault(100e9);

        assertEq(inventory.activePrincipalOhm(), 0, "active principal");
        assertEq(inventory.suppliedOhm(), 100e9, "claim");
        assertEq(inventory.suppliedIdleOhm(), 0, "idle");
        _assertInventoryInvariant();
    }

    //     replenishes that unchanged claim before any OHM is burned
    // Scenarios: BLINV-DEFAULT-P02.
    function test_givenDefaultThenLaterRepayment_replenishesSurvivingClaim(
        uint128 defaultAmount_
    ) public {
        defaultAmount_ = uint128(bound(defaultAmount_, 1, 100e9 - 1));
        uint128 repaymentAmount = 100e9 - defaultAmount_;
        vm.prank(address(facility));
        inventory.settleDefault(defaultAmount_);
        _transferRepayment(repaymentAmount);

        vm.prank(address(facility));
        inventory.settleRepayment(repaymentAmount);

        assertEq(inventory.activePrincipalOhm(), 0, "remaining principal repaid");
        assertEq(inventory.suppliedOhm(), 100e9, "claim survives default");
        assertEq(inventory.suppliedIdleOhm(), repaymentAmount, "later repayment replenishes claim");
        assertEq(ohm.balanceOf(address(inventory)), repaymentAmount, "replenished OHM retained");
        vm.prank(provider);
        inventory.withdraw(repaymentAmount, provider);
        assertEq(
            inventory.providerClaimOhm(provider),
            defaultAmount_,
            "Only unreplenished claim remains"
        );
        assertEq(inventory.suppliedIdleOhm(), 0, "Replenished funding withdrawn");
        assertEq(ohm.balanceOf(provider), repaymentAmount, "Provider receives recovered funding");
        _assertInventoryInvariant();
    }

    function test_givenRepeatedDefault_reverts() public {
        vm.prank(address(facility));
        inventory.settleDefault(100e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_ExcessivePrincipal.selector,
                1,
                0
            )
        );
        vm.prank(address(facility));
        inventory.settleDefault(1);

        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-DEFAULT-N01.
    function test_givenZeroAmount_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAmount.selector);
        vm.prank(address(facility));
        inventory.settleDefault(0);

        assertEq(inventory.activePrincipalOhm(), 100e9, "active principal unchanged");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-DEFAULT-N02.
    function test_givenAmountAbovePrincipal_reverts(uint128 excess_) public {
        excess_ = uint128(bound(excess_, 1, type(uint128).max - 100e9));
        uint128 amount = 100e9 + excess_;
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_ExcessivePrincipal.selector,
                amount,
                100e9
            )
        );
        vm.prank(address(facility));
        inventory.settleDefault(amount);

        assertEq(inventory.activePrincipalOhm(), 100e9, "active principal unchanged");
        _assertInventoryInvariant();
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != address(facility));
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.settleDefault(1e9);
    }

    // Scenarios: BLINV-DEFAULT-P01.
    function test_givenApprovalRestorationFailure_defersToAdminWithoutReverting(
        uint128 amount_
    ) public {
        amount_ = uint128(bound(amount_, 1, 100e9));
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.increaseMintApproval, (address(inventory), amount_)),
            failure
        );

        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.ApprovalRestorationFailed(amount_, failure);
        vm.prank(address(facility));
        inventory.settleDefault(amount_);

        assertEq(inventory.activePrincipalOhm(), 100e9 - amount_, "default recorded");
        assertEq(
            inventory.desiredMintApproval() - mintr.mintApproval(address(inventory)),
            amount_,
            "approval deficit"
        );
        _assertInventoryInvariant();
    }

    function test_givenGloballyDisabled_reverts() public {
        _disableInventory();

        _expectNotEnabled();
        vm.prank(address(facility));
        inventory.settleDefault(40e9);
    }

    function test_givenActiveSameKernelNonFacility_reverts() public {
        _expectNotAuthorised();
        vm.prank(address(config));
        inventory.settleDefault(1e9);
    }

    // Scenarios: BLINV-DEFAULT-P03.
    function test_givenInactiveEnabledInventory_whenAction_reverts() public {
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(address(facility));
        inventory.settleDefault(1);
        assertEq(_accountingState(), beforeState, "Inactive call preserves accounting");
        _reactivateInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.PrincipalDefaulted(1);
        vm.prank(address(facility));
        inventory.settleDefault(1);
        assertEq(inventory.activePrincipalOhm(), 100e9 - 1, "Principal defaulted once");
        assertEq(inventory.providerClaimOhm(provider), 100e9, "Claim preserved");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-L01, BLINV-DRAW-L01, BLINV-MINT-APPROVAL-L01, BLINV-REPAYMENT-L01, BLINV-DEFAULT-L01, BLINV-WITHDRAW-L01.
    function test_givenPausedInventory_whenAction_reverts() public {
        _disableInventory();
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(address(facility));
        inventory.settleDefault(1);
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-SUPPLY-L04, BLINV-DRAW-L03, BLINV-MINT-APPROVAL-L03, BLINV-REPAYMENT-L03, BLINV-DEFAULT-L03, BLINV-WITHDRAW-L03.
    function test_givenInactiveDisabledInventory_whenAction_reverts() public {
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(address(facility));
        inventory.settleDefault(1);
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-DEFAULT-L04.
    function test_givenReEnabledInventory_whenAction_succeeds() public {
        _disableInventory();
        _reEnableInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.PrincipalDefaulted(1);
        vm.prank(address(facility));
        inventory.settleDefault(1);
        assertEq(inventory.activePrincipalOhm(), 100e9 - 1, "Principal defaulted once");
        assertEq(inventory.providerClaimOhm(provider), 100e9, "Claim preserved");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-L02, BLINV-DRAW-L01, BLINV-REPAYMENT-L01, BLINV-DEFAULT-L01, BLINV-WITHDRAW-L01.
    function test_givenPausedInventory_whenZeroAmount_reverts() public {
        _disableInventory();
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(address(facility));
        inventory.settleDefault(0);
        assertEq(_accountingState(), beforeState, "Pause precedes zero input");
    }

    // Scenarios: BLINV-DEFAULT-L03.
    function test_givenInactiveDisabledInventory_whenZeroAmount_reverts() public {
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(address(facility));
        inventory.settleDefault(0);
        assertEq(_accountingState(), beforeState, "Pause precedes zero input");
    }

    // Scenarios: BLINV-DEFAULT-A01.
    function test_whenUnauthorizedCallerWithZeroOrOne_reverts(address caller_) public {
        vm.assume(caller_ != address(facility));
        bytes32 beforeState = _accountingState();
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.settleDefault(0);
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.settleDefault(1);
        assertEq(_accountingState(), beforeState, "Unauthorized calls preserve accounting");
    }

    // Scenarios: BLINV-DEFAULT-D01.
    function test_givenExcessApprovalReductionFails_whenDefaulted_reverts() public {
        vm.prank(address(inventory));
        mintr.increaseMintApproval(address(inventory), type(uint256).max);
        bytes32 beforeState = _accountingState();
        vm.mockCallRevert(
            address(mintr),
            abi.encodeWithSelector(MINTRv1.decreaseMintApproval.selector),
            abi.encodeWithSelector(ApprovalChangeFailed.selector)
        );
        vm.expectRevert(ApprovalChangeFailed.selector);
        vm.prank(address(facility));
        inventory.settleDefault(1);
        assertEq(_accountingState(), beforeState, "Principal and excess approval roll back");
    }

    error ApprovalChangeFailed();

    // Scenarios: BLINV-DEFAULT-N03.
    function test_givenMaximumPrincipal_whenDefaulted() public {
        _enableAndSetCap(type(uint128).max);
        _draw(type(uint128).max - 100e9);
        uint256 balanceBefore = ohm.balanceOf(address(inventory));
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.PrincipalDefaulted(type(uint128).max);
        vm.prank(address(facility));
        inventory.settleDefault(type(uint128).max);
        assertEq(inventory.activePrincipalOhm(), 0, "Maximum principal fully defaulted");
        assertEq(inventory.providerClaimOhm(provider), 100e9, "Claim survives maximum default");
        assertEq(ohm.balanceOf(address(inventory)), balanceBefore, "No token movement");
        assertEq(
            mintr.mintApproval(address(inventory)),
            type(uint128).max,
            "Approval restored up to cap"
        );
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-DEFAULT-N02, BLINV-DEFAULT-N03.
    function test_whenDefaultBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenPartialDefault_preservesClaim(1);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore one-unit default seed");
        test_givenAmountAbovePrincipal_reverts(1);
        test_givenAmountAbovePrincipal_reverts(type(uint128).max - 100e9);
        test_givenMaximumPrincipal_whenDefaulted();
    }

    // Scenarios: BLINV-DEFAULT-L01, BLINV-DEFAULT-L03.
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

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
