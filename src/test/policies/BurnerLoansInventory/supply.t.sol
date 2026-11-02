// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Libraries
import {stdError} from "@forge-std-1.16.2/StdError.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {BURNER_LOANS_INVENTORY_PROVIDER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.

contract BurnerLoansInventorySupplyTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
    }

    // Scenarios: BLINV-SUPPLY-L03, BLINV-SUPPLY-N02.
    function test_givenProvider_updatesAccountingAndEmits(uint128 amount) public {
        amount = uint128(bound(amount, 1, type(uint128).max));
        ohm.mint(provider, amount);
        vm.startPrank(provider);
        ohm.approve(address(inventory), amount);
        vm.expectEmit(true, false, false, true, address(inventory));
        emit IBurnerLoansInventory.OhmSupplied(provider, amount, amount, amount);
        inventory.supply(amount);
        vm.stopPrank();
        assertEq(ohm.balanceOf(provider), 0, "Payer debited exactly");
        assertEq(ohm.balanceOf(address(inventory)), amount, "Exact incoming receipt");
        assertEq(inventory.suppliedOhm(), amount, "claim");
        assertEq(inventory.providerClaimOhm(provider), amount, "provider claim");
        assertEq(inventory.suppliedIdleOhm(), amount, "idle");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-N01.
    function test_givenZeroAmount_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAmount.selector);
        vm.prank(provider);
        inventory.supply(0);

        _assertInventoryInvariant();
    }

    function test_givenGloballyDisabled_reverts() public {
        _disableInventory();

        _expectNotEnabled();
        vm.prank(provider);
        inventory.supply(1);
    }

    // Scenarios: BLINV-SUPPLY-A01.
    function test_givenCallerWithoutProviderRole_reverts(address caller_) public {
        vm.assume(caller_ != provider);
        _expectRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE);
        vm.prank(caller_);
        inventory.supply(1);
    }

    // Scenarios: BLINV-SUPPLY-D01.
    function test_givenMissingAllowance_reverts(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        ohm.mint(provider, amount_);
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(provider);
        inventory.supply(amount_);
    }

    // Scenarios: BLINV-SUPPLY-D02.
    function test_givenMissingBalance_reverts(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        vm.prank(provider);
        ohm.approve(address(inventory), amount_);
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(provider);
        inventory.supply(amount_);
    }

    // Scenarios: BLINV-SUPPLY-D03.
    function test_givenExistingBalance_givenUnderDeliveredTransfer_reverts() public {
        uint128 amount = 10e9;
        uint128 existingBalance = 25e9;
        ohm.mint(address(inventory), existingBalance);
        ohm.mint(provider, amount);
        vm.prank(provider);
        ohm.approve(address(inventory), amount);
        vm.mockCall(
            address(ohm),
            abi.encodeCall(ohm.transferFrom, (provider, address(inventory), amount)),
            abi.encode(true)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(ohm),
                address(inventory),
                amount,
                0
            )
        );
        vm.prank(provider);
        inventory.supply(amount);

        assertEq(ohm.balanceOf(provider), amount, "provider balance rollback");
        assertEq(ohm.balanceOf(address(inventory)), existingBalance, "existing balance preserved");
        assertEq(inventory.providerClaimOhm(provider), 0, "provider claim rollback");
        assertEq(inventory.suppliedOhm(), 0, "aggregate claim rollback");
        assertEq(inventory.suppliedIdleOhm(), 0, "idle accounting rollback");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-N02.
    function test_givenMultipleProviders_recordsSeparateClaims() public {
        address secondProvider = makeAddr("secondProvider");
        vm.prank(admin);
        rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, secondProvider);

        _supply(100e9);
        ohm.mint(secondProvider, 40e9);
        vm.startPrank(secondProvider);
        ohm.approve(address(inventory), 40e9);
        inventory.supply(40e9);
        vm.stopPrank();

        assertEq(inventory.providerClaimOhm(provider), 100e9, "first provider claim");
        assertEq(inventory.providerClaimOhm(secondProvider), 40e9, "second provider claim");
        assertEq(inventory.suppliedOhm(), 140e9, "aggregate claim");
        assertEq(inventory.suppliedIdleOhm(), 140e9, "aggregate idle");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-P01.
    function test_givenInactiveEnabledInventory_whenAction_reverts() public {
        ohm.mint(provider, 1);
        vm.prank(provider);
        ohm.approve(address(inventory), 1);
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(provider);
        inventory.supply(1);
        assertEq(_accountingState(), beforeState, "Inactive call preserves accounting");
        _reactivateInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.OhmSupplied(provider, 1, 1, 1);
        vm.prank(provider);
        inventory.supply(1);
        assertEq(inventory.providerClaimOhm(provider), 1, "One provider credit");
        assertEq(ohm.balanceOf(address(inventory)), 1, "Exact receipt");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-L01, BLINV-DRAW-L01, BLINV-MINT-APPROVAL-L01, BLINV-REPAYMENT-L01, BLINV-DEFAULT-L01, BLINV-WITHDRAW-L01.
    function test_givenPausedInventory_whenAction_reverts() public {
        ohm.mint(provider, 1);
        vm.prank(provider);
        ohm.approve(address(inventory), 1);
        _disableInventory();
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(provider);
        inventory.supply(1);
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-SUPPLY-L04, BLINV-DRAW-L03, BLINV-MINT-APPROVAL-L03, BLINV-REPAYMENT-L03, BLINV-DEFAULT-L03, BLINV-WITHDRAW-L03.
    function test_givenInactiveDisabledInventory_whenAction_reverts() public {
        ohm.mint(provider, 1);
        vm.prank(provider);
        ohm.approve(address(inventory), 1);
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(provider);
        inventory.supply(1);
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-SUPPLY-L05.
    function test_givenReEnabledInventory_whenAction_succeeds() public {
        ohm.mint(provider, 1);
        vm.prank(provider);
        ohm.approve(address(inventory), 1);
        _disableInventory();
        _reEnableInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.OhmSupplied(provider, 1, 1, 1);
        vm.prank(provider);
        inventory.supply(1);
        assertEq(inventory.providerClaimOhm(provider), 1, "One provider credit");
        assertEq(ohm.balanceOf(address(inventory)), 1, "Exact receipt");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-L02, BLINV-DRAW-L01, BLINV-REPAYMENT-L01, BLINV-DEFAULT-L01, BLINV-WITHDRAW-L01.
    function test_givenPausedInventory_whenZeroAmount_reverts() public {
        _disableInventory();
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(provider);
        inventory.supply(0);
        assertEq(_accountingState(), beforeState, "Pause precedes zero input");
    }

    // Scenarios: BLINV-SUPPLY-L03.
    function test_givenInactiveDisabledInventory_whenZeroAmount_reverts() public {
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(provider);
        inventory.supply(0);
        assertEq(_accountingState(), beforeState, "Pause precedes zero input");
    }

    // Scenarios: BLINV-SUPPLY-D05.
    function test_givenApprovalReductionFailure_whenSupplied_reverts() public {
        ohm.mint(provider, 10);
        vm.prank(provider);
        ohm.approve(address(inventory), 10);
        bytes32 beforeState = _accountingState();
        vm.mockCallRevert(
            address(mintr),
            abi.encodeWithSelector(MINTRv1.decreaseMintApproval.selector),
            abi.encodeWithSelector(ApprovalChangeFailed.selector)
        );
        vm.expectRevert(ApprovalChangeFailed.selector);
        vm.prank(provider);
        inventory.supply(10);
        assertEq(_accountingState(), beforeState, "Incoming transfer and credits roll back");
    }

    error ApprovalChangeFailed();

    // Scenarios: BLINV-SUPPLY-N02.
    function test_whenSupplyBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenProvider_updatesAccountingAndEmits(1);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore empty supply fixture");
        test_givenProvider_updatesAccountingAndEmits(type(uint128).max);
    }

    // Scenarios: BLINV-SUPPLY-L01, BLINV-SUPPLY-L02, BLINV-SUPPLY-L04.
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

    function _expectSupplyOverflow(address provider_) internal {
        ohm.mint(provider_, 1);
        vm.prank(provider_);
        assertTrue(ohm.approve(address(inventory), 1), "Provider approves one unit");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(128),
                uint256(type(uint128).max) + 1
            )
        );
        vm.prank(provider_);
        inventory.supply(1);
        assertEq(ohm.balanceOf(provider_), 1, "Overflow does not spend provider funds");
        assertEq(ohm.allowance(provider_, address(inventory)), 1, "Overflow preserves allowance");
        assertEq(inventory.suppliedOhm(), type(uint128).max, "Aggregate claim preserved");
    }

    // Scenarios: BLINV-SUPPLY-N03.
    function test_givenMaximumProviderClaim_whenOneUnitSupplied_reverts() public {
        _supply(type(uint128).max);
        _expectSupplyOverflow(provider);
        assertEq(
            inventory.providerClaimOhm(provider),
            type(uint128).max,
            "Provider claim preserved"
        );
        assertEq(inventory.suppliedIdleOhm(), type(uint128).max, "Idle funding preserved");
    }

    // Scenarios: BLINV-SUPPLY-N04.
    function test_givenMaximumIdle_whenAnotherProviderSuppliesOne_reverts() public {
        _supply(type(uint128).max);
        vm.prank(admin);
        rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, outsider);
        _expectSupplyOverflow(outsider);
        assertEq(inventory.providerClaimOhm(outsider), 0, "Earlier caller credit rolls back");
        assertEq(inventory.suppliedIdleOhm(), type(uint128).max, "Idle funding preserved");
    }

    // Scenarios: BLINV-SUPPLY-N05.
    function test_givenMaximumClaimsAndOneUnitDrawn_whenAnotherProviderSuppliesOne_reverts()
        public
    {
        _supply(type(uint128).max);
        _draw(1);
        vm.prank(admin);
        rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, address(0xcafe));
        _expectSupplyOverflow(address(0xcafe));
        assertEq(
            inventory.providerClaimOhm(address(0xcafe)),
            0,
            "Earlier caller credit rolls back"
        );
        assertEq(
            inventory.suppliedIdleOhm(),
            uint256(type(uint128).max) - 1,
            "Earlier idle credit rolls back"
        );
        assertEq(inventory.activePrincipalOhm(), 1, "Outstanding principal unchanged");
    }

    // Scenarios: BLINV-SUPPLY-L04, BLINV-SUPPLY-P01.
    function test_givenInactive_whenUnauthorizedAndInvalid_reverts(
        address caller_,
        bool enabled_
    ) public {
        vm.assume(caller_ != provider);
        if (!enabled_) _disableInventory();
        _deactivateInventory();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(inventory)
            )
        );
        vm.prank(caller_);
        inventory.supply(0);
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
