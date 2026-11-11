// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

// Interfaces

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Contracts

import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {BurnerLoansInventoryTest} from "src/test/policies/BurnerLoansInventory/BurnerLoansInventoryTest.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.

contract BurnerLoansInventorySettleRepaymentTest is BurnerLoansInventoryTest {
    uint128 internal constant ACTIVE_PRINCIPAL = 500e9;
    uint128 internal constant SUPPLIED_CLAIM = 300e9;

    event RepaymentSettled(uint256 amount, uint256 retainedAmount, uint256 burnedAmount);

    function setUp() public override {
        super.setUp();
        _enableAndSetCap(1_000e9);
        _supply(300e9);
        vm.prank(address(facility));
        inventory.draw(recipient, 500e9);
    }

    // Scenarios: BLINV-REPAYMENT-L02, BLINV-REPAYMENT-N03.
    function test_givenClaimDeficit_retainsRepayment(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, SUPPLIED_CLAIM));
        _transferRepayment(amount_);

        vm.expectEmit(true, true, true, true, address(inventory));
        emit RepaymentSettled(amount_, amount_, 0);
        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        // active = 500e9 - amount_ (9 decimals); retained idle = amount_ (9 decimals).
        assertEq(inventory.activePrincipalOhm(), ACTIVE_PRINCIPAL - amount_, "active principal");
        assertEq(inventory.suppliedIdleOhm(), amount_, "supplied idle");
        assertEq(inventory.suppliedOhm(), SUPPLIED_CLAIM, "supplied claim");
        assertEq(mintr.mintApproval(address(inventory)), 500e9, "mint approval");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-REPAYMENT-N03.
    function test_givenClaimReplenished_burnsRepayment(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, ACTIVE_PRINCIPAL - SUPPLIED_CLAIM));
        _transferRepayment(SUPPLIED_CLAIM);
        vm.prank(address(facility));
        inventory.settleRepayment(SUPPLIED_CLAIM);
        _transferRepayment(amount_);

        uint256 supplyBefore = ohm.totalSupply();
        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        // active = 500e9 - 300e9 - amount_; approval = 500e9 + burned amount_.
        assertEq(
            inventory.activePrincipalOhm(),
            ACTIVE_PRINCIPAL - SUPPLIED_CLAIM - amount_,
            "active principal"
        );
        assertEq(inventory.suppliedIdleOhm(), SUPPLIED_CLAIM, "supplied idle");
        assertEq(ohm.totalSupply(), supplyBefore - amount_, "burned amount");
        assertEq(mintr.mintApproval(address(inventory)), 500e9 + amount_, "mint approval");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-REPAYMENT-L02, BLINV-REPAYMENT-N03.
    function test_givenRepaymentCrossesClaimDeficit_splitsRetentionAndBurn(uint128 amount_) public {
        amount_ = uint128(bound(amount_, SUPPLIED_CLAIM + 1, ACTIVE_PRINCIPAL));
        uint128 burnedAmount = amount_ - SUPPLIED_CLAIM;
        _transferRepayment(amount_);
        uint256 supplyBefore = ohm.totalSupply();

        vm.expectEmit(true, true, true, true, address(inventory));
        emit RepaymentSettled(amount_, SUPPLIED_CLAIM, burnedAmount);
        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        // active = 500e9 - amount_; approval = 500e9 + (amount_ - 300e9).
        assertEq(inventory.activePrincipalOhm(), ACTIVE_PRINCIPAL - amount_, "active principal");
        assertEq(inventory.suppliedIdleOhm(), SUPPLIED_CLAIM, "supplied idle");
        assertEq(ohm.totalSupply(), supplyBefore - burnedAmount, "burned amount");
        assertEq(mintr.mintApproval(address(inventory)), 500e9 + burnedAmount, "mint approval");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-REPAYMENT-P01.
    function test_givenBurnFailure_settlesAndLeavesSurplus(uint128 burnAmount_) public {
        burnAmount_ = uint128(bound(burnAmount_, 1, 200e9));
        uint128 repaymentAmount = 300e9 + burnAmount_;
        _transferRepayment(repaymentAmount);
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.burnOhm, (address(inventory), burnAmount_)),
            failure
        );

        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.OhmBurnFailed(burnAmount_, failure);
        vm.prank(address(facility));
        inventory.settleRepayment(repaymentAmount);

        assertEq(inventory.activePrincipalOhm(), 200e9 - burnAmount_, "active principal settled");
        assertEq(inventory.suppliedIdleOhm(), 300e9, "provider claim replenished");
        assertEq(inventory.suppliedOhm(), 300e9, "claim unchanged");
        assertEq(inventory.surplusOhm(), burnAmount_, "failed burn surplus");
        assertEq(ohm.balanceOf(address(inventory)), repaymentAmount, "retained and surplus OHM");
        assertEq(mintr.mintApproval(address(inventory)), 500e9, "mint approval unchanged");
        assertEq(
            inventory.desiredMintApproval() - mintr.mintApproval(address(inventory)),
            burnAmount_,
            "mint approval deficit"
        );
        _assertInventoryInvariant();
    }

    function test_givenNoSuppliedOhm_burnsFullRepayment(uint128 amount_) public {
        _transferRepayment(300e9);
        vm.prank(address(facility));
        inventory.settleRepayment(300e9);
        vm.prank(provider);
        inventory.withdraw(300e9, recipient);

        amount_ = uint128(bound(amount_, 1, 200e9));
        _transferRepayment(amount_);
        uint256 supplyBefore = ohm.totalSupply();

        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        assertEq(ohm.totalSupply(), supplyBefore - amount_, "full repayment burned");
        _assertInventoryState(address(inventory), 0, 200e9 - amount_, 0, 0, 800e9 + amount_);
    }

    // Scenarios: BLINV-REPAYMENT-N02.
    function test_givenAmountAbovePrincipal_reverts(uint128 excess_) public {
        excess_ = uint128(bound(excess_, 1, type(uint128).max - 500e9));
        uint128 amount = 500e9 + excess_;
        ohm.mint(address(inventory), amount);
        vm.prank(address(facility));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_ExcessivePrincipal.selector,
                amount,
                500e9
            )
        );
        inventory.settleRepayment(amount);
        assertEq(inventory.activePrincipalOhm(), 500e9, "active principal unchanged");
    }

    // Scenarios: BLINV-REPAYMENT-N01.
    function test_givenZeroAmount_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAmount.selector);
        vm.prank(address(facility));
        inventory.settleRepayment(0);

        assertEq(inventory.activePrincipalOhm(), 500e9, "active principal unchanged");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-REPAYMENT-D01.
    function test_givenInsufficientReceivedBalance_reverts(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 500e9));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientBalance.selector,
                amount_,
                0
            )
        );
        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        assertEq(inventory.activePrincipalOhm(), 500e9, "active principal unchanged");
        _assertInventoryInvariant();
    }

    function test_givenGloballyDisabled_reverts() public {
        _disableInventory();
        ohm.mint(address(inventory), 1e9);
        vm.prank(address(facility));
        _expectNotEnabled();
        inventory.settleRepayment(1e9);
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != address(facility));
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.settleRepayment(1e9);
    }

    // Scenarios: BLINV-REPAYMENT-P02.
    function test_givenApprovalRestorationFailure_defersToAdminWithoutReverting(
        uint128 amount_
    ) public {
        amount_ = uint128(bound(amount_, 1, ACTIVE_PRINCIPAL - SUPPLIED_CLAIM));
        _transferRepayment(SUPPLIED_CLAIM);
        vm.prank(address(facility));
        inventory.settleRepayment(SUPPLIED_CLAIM);
        _transferRepayment(amount_);
        bytes memory failure = abi.encodeWithSelector(MINTRv1.MINTR_NotApproved.selector);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeCall(MINTRv1.increaseMintApproval, (address(inventory), amount_)),
            failure
        );

        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.ApprovalRestorationFailed(amount_, failure);
        vm.prank(address(facility));
        inventory.settleRepayment(amount_);

        assertEq(
            inventory.activePrincipalOhm(),
            ACTIVE_PRINCIPAL - SUPPLIED_CLAIM - amount_,
            "principal settled"
        );
        assertEq(
            inventory.desiredMintApproval() - mintr.mintApproval(address(inventory)),
            amount_,
            "approval deficit"
        );
        _assertInventoryInvariant();
    }

    function test_givenActiveSameKernelNonFacility_reverts() public {
        _expectNotAuthorised();
        vm.prank(address(config));
        inventory.settleRepayment(1e9);
    }

    // Scenarios: BLINV-REPAYMENT-P04.
    function test_givenInactiveEnabledInventory_whenAction_reverts() public {
        _transferRepayment(1);
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(address(facility));
        inventory.settleRepayment(1);
        assertEq(_accountingState(), beforeState, "Inactive call preserves accounting");
        _reactivateInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.RepaymentSettled(1, 1, 0);
        vm.prank(address(facility));
        inventory.settleRepayment(1);
        assertEq(inventory.activePrincipalOhm(), 500e9 - 1, "Principal settled once");
        assertEq(inventory.suppliedIdleOhm(), 1, "Receipt retained");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-L01, BLINV-DRAW-L01, BLINV-MINT-APPROVAL-L01, BLINV-REPAYMENT-L01, BLINV-DEFAULT-L01, BLINV-WITHDRAW-L01.
    function test_givenPausedInventory_whenAction_reverts() public {
        _transferRepayment(1);
        _disableInventory();
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(address(facility));
        inventory.settleRepayment(1);
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-SUPPLY-L04, BLINV-DRAW-L03, BLINV-MINT-APPROVAL-L03, BLINV-REPAYMENT-L03, BLINV-DEFAULT-L03, BLINV-WITHDRAW-L03.
    function test_givenInactiveDisabledInventory_whenAction_reverts() public {
        _transferRepayment(1);
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(address(facility));
        inventory.settleRepayment(1);
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-REPAYMENT-L04.
    function test_givenReEnabledInventory_whenAction_succeeds() public {
        _transferRepayment(1);
        _disableInventory();
        _reEnableInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.RepaymentSettled(1, 1, 0);
        vm.prank(address(facility));
        inventory.settleRepayment(1);
        assertEq(inventory.activePrincipalOhm(), 500e9 - 1, "Principal settled once");
        assertEq(inventory.suppliedIdleOhm(), 1, "Receipt retained");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-L02, BLINV-DRAW-L01, BLINV-REPAYMENT-L01, BLINV-DEFAULT-L01, BLINV-WITHDRAW-L01.
    function test_givenPausedInventory_whenZeroAmount_reverts() public {
        _disableInventory();
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(address(facility));
        inventory.settleRepayment(0);
        assertEq(_accountingState(), beforeState, "Pause precedes zero input");
    }

    // Scenarios: BLINV-REPAYMENT-L03.
    function test_givenInactiveDisabledInventory_whenZeroAmount_reverts() public {
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(address(facility));
        inventory.settleRepayment(0);
        assertEq(_accountingState(), beforeState, "Pause precedes zero input");
    }

    // Scenarios: BLINV-REPAYMENT-A01.
    function test_whenUnauthorizedCallerWithZeroOrOne_reverts(address caller_) public {
        vm.assume(caller_ != address(facility));
        bytes32 beforeState = _accountingState();
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.settleRepayment(0);
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.settleRepayment(1);
        assertEq(_accountingState(), beforeState, "Unauthorized calls preserve accounting");
    }

    // Scenarios: BLINV-REPAYMENT-P03.
    function test_givenDonation_whenRepaid_preservesSurplus() public {
        ohm.mint(address(inventory), 7);
        _transferRepayment(500e9);
        vm.prank(address(facility));
        inventory.settleRepayment(500e9);
        assertEq(inventory.surplusOhm(), 7, "Donation remains ordinary surplus");
        assertEq(inventory.suppliedIdleOhm(), 300e9, "Only claim deficit retained");
        assertEq(inventory.activePrincipalOhm(), 0, "Debt settled");
    }

    // Scenarios: BLINV-REPAYMENT-D02.
    function test_givenBurnThenApprovalReductionFails_whenRepaid_reverts() public {
        _transferRepayment(500e9);
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
        inventory.settleRepayment(500e9);
        assertEq(_accountingState(), beforeState, "Successful burn and settlement both roll back");
    }

    error ApprovalChangeFailed();

    // Scenarios: BLINV-REPAYMENT-N03.
    function test_givenMaximumPrincipal_whenRepaid() public {
        _enableAndSetCap(type(uint128).max);
        _draw(type(uint128).max - 500e9);
        _transferRepayment(type(uint128).max);
        uint256 supplyBefore = ohm.totalSupply();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.RepaymentSettled(
            type(uint128).max,
            300e9,
            uint256(type(uint128).max) - 300e9
        );
        vm.prank(address(facility));
        inventory.settleRepayment(type(uint128).max);
        assertEq(inventory.activePrincipalOhm(), 0, "Maximum principal settled");
        assertEq(inventory.suppliedIdleOhm(), 300e9, "Provider claim replenished");
        assertEq(
            ohm.totalSupply(),
            supplyBefore - (uint256(type(uint128).max) - 300e9),
            "Excess burned"
        );
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-REPAYMENT-N02, BLINV-REPAYMENT-N03.
    function test_whenRepaymentBoundarySeeds() public {
        uint128[3] memory retainedAmounts = [uint128(1), SUPPLIED_CLAIM - 1, SUPPLIED_CLAIM];
        for (uint256 i; i < retainedAmounts.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            test_givenClaimDeficit_retainsRepayment(retainedAmounts[i]);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore retained repayment seed");
        }
        uint128[2] memory burnAmounts = [SUPPLIED_CLAIM + 1, ACTIVE_PRINCIPAL];
        for (uint256 i; i < burnAmounts.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            test_givenRepaymentCrossesClaimDeficit_splitsRetentionAndBurn(burnAmounts[i]);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore split repayment seed");
        }
        uint256 snapshot = vm.snapshotState();
        test_givenAmountAbovePrincipal_reverts(1);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore excess repayment seed");
        snapshot = vm.snapshotState();
        test_givenAmountAbovePrincipal_reverts(type(uint128).max - ACTIVE_PRINCIPAL);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore maximum excess seed");
        test_givenMaximumPrincipal_whenRepaid();
    }

    // Scenarios: BLINV-REPAYMENT-L01, BLINV-REPAYMENT-L03.
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
