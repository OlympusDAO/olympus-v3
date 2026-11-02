// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

// Interfaces

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Libraries
import {BURNER_LOANS_INVENTORY_PROVIDER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.

contract BurnerLoansInventoryWithdrawTest is BurnerLoansInventoryTest {
    error TransferFailed();

    function setUp() public override {
        super.setUp();
        _enableAndSetCap(DEFAULT_CAP);
    }

    // Scenarios: BLINV-WITHDRAW-L02, BLINV-WITHDRAW-P01.
    function test_givenIdleClaim_withdrawsExactAmount(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 100e9));
        _supply(100e9);
        vm.expectEmit(true, false, false, true, address(inventory));
        emit IBurnerLoansInventory.OhmWithdrawn(
            provider,
            amount_,
            100e9 - amount_,
            100e9 - amount_
        );
        vm.prank(provider);
        inventory.withdraw(amount_, recipient);
        assertEq(inventory.suppliedOhm(), 100e9 - amount_, "claim");
        assertEq(inventory.providerClaimOhm(provider), 100e9 - amount_, "provider claim");
        assertEq(inventory.suppliedIdleOhm(), 100e9 - amount_, "idle");
        assertEq(ohm.balanceOf(recipient), amount_, "recipient balance");
        assertEq(
            mintr.mintApproval(address(inventory)),
            DEFAULT_CAP - 100e9 + amount_,
            "Exact restored approval"
        );
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-WITHDRAW-P01.
    function test_givenFullIdleClaim_withdrawsAll() public {
        _supply(100e9);
        vm.prank(provider);
        inventory.withdraw(100e9, recipient);

        assertEq(inventory.providerClaimOhm(provider), 0, "provider claim");
        assertEq(inventory.suppliedOhm(), 0, "aggregate claim");
        assertEq(inventory.suppliedIdleOhm(), 0, "idle");
        assertEq(ohm.balanceOf(recipient), 100e9, "recipient balance");
        _assertInventoryInvariant();
    }

    function test_givenTransferFailure_revertsAndRollsBack(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 100e9));
        _supply(100e9);
        bytes memory failure = abi.encodeWithSelector(TransferFailed.selector);
        vm.mockCallRevert(
            address(ohm),
            abi.encodeWithSelector(ERC20.transfer.selector, recipient, amount_),
            failure
        );

        vm.expectRevert(failure);
        vm.prank(provider);
        inventory.withdraw(amount_, recipient);

        assertEq(inventory.providerClaimOhm(provider), 100e9, "provider claim rolled back");
        assertEq(inventory.suppliedOhm(), 100e9, "aggregate claim rolled back");
        assertEq(inventory.suppliedIdleOhm(), 100e9, "idle rolled back");
        assertEq(ohm.balanceOf(recipient), 0, "recipient unchanged");
        _assertInventoryInvariant();
    }

    function test_givenGloballyDisabled_reverts() public {
        _supply(100e9);
        _disableInventory();

        _expectNotEnabled();
        vm.prank(provider);
        inventory.withdraw(40e9, recipient);
    }

    function test_givenAnotherProviderClaim_reverts() public {
        address secondProvider = makeAddr("secondProvider");
        vm.prank(admin);
        rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, secondProvider);
        _supply(100e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientClaim.selector,
                1,
                0
            )
        );
        vm.prank(secondProvider);
        inventory.withdraw(1, recipient);
    }

    function test_givenAmountAboveIdle_reverts(uint128 excess_) public {
        excess_ = uint128(bound(excess_, 1, 60e9));
        uint128 amount = 40e9 + excess_;
        _supply(100e9);
        _draw(60e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientIdle.selector,
                amount,
                40e9
            )
        );
        vm.prank(provider);
        inventory.withdraw(amount, recipient);

        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-WITHDRAW-N01.
    function test_givenZeroAmount_reverts() public {
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAmount.selector);
        vm.prank(provider);
        inventory.withdraw(0, recipient);
    }

    // Scenarios: BLINV-WITHDRAW-I01.
    function test_givenZeroRecipient_reverts() public {
        _supply(1);
        vm.expectRevert(IBurnerLoansInventory.BurnerLoansInventory_ZeroAddress.selector);
        vm.prank(provider);
        inventory.withdraw(1, address(0));
    }

    // Scenarios: BLINV-WITHDRAW-A01.
    function test_givenProviderRoleRevoked_preservesClaimAndReverts() public {
        _supply(100e9);
        vm.prank(admin);
        rolesAdmin.revokeRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, provider);

        _expectRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE);
        vm.prank(provider);
        inventory.withdraw(1, recipient);
        assertEq(inventory.providerClaimOhm(provider), 100e9, "provider claim preserved");
        assertEq(inventory.suppliedOhm(), 100e9, "aggregate claim preserved");
        vm.prank(admin);
        rolesAdmin.grantRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE, provider);
        vm.prank(provider);
        inventory.withdraw(1, provider);
        assertEq(ohm.balanceOf(provider), 1, "Provider exit restored with role");
        assertEq(inventory.providerClaimOhm(provider), 100e9 - 1, "Remaining claim exact");
    }

    function test_givenIdleStillAtCap_capsApprovalRestoration() public {
        _supply(DEFAULT_CAP + 100e9);
        vm.prank(provider);
        inventory.withdraw(100e9, recipient);
        assertEq(inventory.desiredMintApproval(), 0, "desired approval");
        assertEq(mintr.mintApproval(address(inventory)), 0, "actual approval");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-WITHDRAW-P02.
    function test_givenExternalOverApproval_reducesApprovalToDesired(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 100e9));
        _supply(100e9);
        vm.prank(address(inventory));
        mintr.increaseMintApproval(address(inventory), type(uint256).max);

        vm.prank(provider);
        inventory.withdraw(amount_, recipient);

        assertEq(
            mintr.mintApproval(address(inventory)),
            inventory.desiredMintApproval(),
            "approval reduced to desired"
        );
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-WITHDRAW-P03.
    function test_givenInactiveEnabledInventory_whenAction_reverts() public {
        _supply(1);
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(provider);
        inventory.withdraw(1, recipient);
        assertEq(_accountingState(), beforeState, "Inactive call preserves accounting");
        _reactivateInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.OhmWithdrawn(provider, 1, 0, 0);
        vm.prank(provider);
        inventory.withdraw(1, recipient);
        assertEq(inventory.providerClaimOhm(provider), 0, "Claim cleared");
        assertEq(ohm.balanceOf(recipient), 1, "Recipient paid");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-L01, BLINV-DRAW-L01, BLINV-MINT-APPROVAL-L01, BLINV-REPAYMENT-L01, BLINV-DEFAULT-L01, BLINV-WITHDRAW-L01.
    function test_givenPausedInventory_whenAction_reverts() public {
        _supply(1);
        _disableInventory();
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(provider);
        inventory.withdraw(1, recipient);
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-SUPPLY-L04, BLINV-DRAW-L03, BLINV-MINT-APPROVAL-L03, BLINV-REPAYMENT-L03, BLINV-DEFAULT-L03, BLINV-WITHDRAW-L03.
    function test_givenInactiveDisabledInventory_whenAction_reverts() public {
        _supply(1);
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(provider);
        inventory.withdraw(1, recipient);
        assertEq(_accountingState(), beforeState, "Paused call preserves accounting");
    }

    // Scenarios: BLINV-WITHDRAW-L04.
    function test_givenReEnabledInventory_whenAction_succeeds() public {
        _supply(1);
        _disableInventory();
        _reEnableInventory();
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.OhmWithdrawn(provider, 1, 0, 0);
        vm.prank(provider);
        inventory.withdraw(1, recipient);
        assertEq(inventory.providerClaimOhm(provider), 0, "Claim cleared");
        assertEq(ohm.balanceOf(recipient), 1, "Recipient paid");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-SUPPLY-L02, BLINV-DRAW-L01, BLINV-REPAYMENT-L01, BLINV-DEFAULT-L01, BLINV-WITHDRAW-L01.
    function test_givenPausedInventory_whenZeroAmount_reverts() public {
        _disableInventory();
        bytes32 beforeState = _accountingState();
        _expectNotEnabled();
        vm.prank(provider);
        inventory.withdraw(0, recipient);
        assertEq(_accountingState(), beforeState, "Pause precedes zero input");
    }

    // Scenarios: BLINV-WITHDRAW-L03.
    function test_givenInactiveDisabledInventory_whenZeroAmount_reverts() public {
        _disableInventory();
        _deactivateInventory();
        bytes32 beforeState = _accountingState();
        _expectInventoryNotActive();
        vm.prank(provider);
        inventory.withdraw(0, recipient);
        assertEq(_accountingState(), beforeState, "Pause precedes zero input");
    }

    // Scenarios: BLINV-WITHDRAW-A02.
    function test_whenUnauthorizedCallerWithZeroOrOne_reverts(address caller_) public {
        vm.assume(caller_ != provider);
        bytes32 beforeState = _accountingState();
        _expectRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE);
        vm.prank(caller_);
        inventory.withdraw(0, recipient);
        _expectRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE);
        vm.prank(caller_);
        inventory.withdraw(1, recipient);
        assertEq(_accountingState(), beforeState, "Unauthorized calls preserve accounting");
    }

    // Scenarios: BLINV-WITHDRAW-N02.
    function test_givenClaim_whenAmountAboveClaim_reverts(uint128 amount_) public {
        _supply(100);
        amount_ = uint128(bound(amount_, 101, type(uint128).max));
        bytes32 beforeState = _accountingState();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientClaim.selector,
                amount_,
                100
            )
        );
        vm.prank(provider);
        inventory.withdraw(amount_, recipient);
        assertEq(_accountingState(), beforeState, "Claim failure preserves custody");
    }

    // Scenarios: BLINV-WITHDRAW-N03.
    function test_givenMaximumClaim_whenAmountAboveIdle_reverts(
        uint128 amount_,
        uint128 idle_
    ) public {
        idle_ = uint128(bound(idle_, 0, type(uint128).max - 1));
        _enableAndSetCap(type(uint128).max);
        _supply(type(uint128).max);
        _draw(type(uint128).max - idle_);
        amount_ = uint128(bound(amount_, uint256(idle_) + 1, type(uint128).max));
        bytes32 beforeState = _accountingState();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientIdle.selector,
                amount_,
                idle_
            )
        );
        vm.prank(provider);
        inventory.withdraw(amount_, recipient);
        assertEq(_accountingState(), beforeState, "Idle failure preserves custody");
    }

    // Scenarios: BLINV-WITHDRAW-P01.
    function test_givenClaim_whenWithdrawnToSelf(uint128 amount_, bool inventoryRecipient_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        _supply(amount_);
        address target = inventoryRecipient_ ? address(inventory) : provider;
        vm.prank(provider);
        inventory.withdraw(amount_, target);
        assertEq(
            ohm.balanceOf(target),
            amount_,
            "Nominal outgoing behavior including self-transfer"
        );
        assertEq(inventory.providerClaimOhm(provider), 0, "Provider claim cleared");
        assertEq(inventory.suppliedOhm(), 0, "Aggregate claim cleared");
        assertEq(inventory.suppliedIdleOhm(), 0, "Idle cleared");
        assertEq(
            inventory.surplusOhm(),
            inventoryRecipient_ ? amount_ : 0,
            "Inventory self-transfer becomes unclaimed surplus"
        );
    }

    // Scenarios: BLINV-WITHDRAW-D01.
    function test_givenApprovalIncreaseFailure_whenWithdrawn_succeeds() public {
        _supply(10);
        vm.mockCallRevert(
            address(mintr),
            abi.encodeWithSelector(MINTRv1.increaseMintApproval.selector),
            abi.encodeWithSelector(ApprovalChangeFailed.selector)
        );
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.ApprovalRestorationFailed(
            10,
            abi.encodeWithSelector(ApprovalChangeFailed.selector)
        );
        vm.prank(provider);
        inventory.withdraw(10, recipient);
        assertEq(ohm.balanceOf(recipient), 10, "Withdrawal paid despite approval failure");
        assertEq(inventory.suppliedOhm(), 0, "Claims cleared");
        assertEq(
            mintr.mintApproval(address(inventory)),
            DEFAULT_CAP - 10,
            "Safe approval deficit retained"
        );
    }

    error ApprovalChangeFailed();

    // Scenarios: BLINV-WITHDRAW-D02.
    function test_givenFalseTransfer_whenWithdrawn_reverts() public {
        _supply(10);
        bytes32 beforeState = _accountingState();
        vm.mockCall(address(ohm), abi.encodeCall(ohm.transfer, (recipient, 10)), abi.encode(false));
        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(ohm))
        );
        vm.prank(provider);
        inventory.withdraw(10, recipient);
        assertEq(
            _accountingState(),
            beforeState,
            "False transfer rolls back restored approval and claims"
        );
    }

    // Scenarios: BLINV-WITHDRAW-N02, BLINV-WITHDRAW-N03, BLINV-WITHDRAW-P01.
    function test_whenWithdrawalBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenClaim_whenAmountAboveClaim_reverts(101);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore claim seed");
        snapshot = vm.snapshotState();
        test_givenClaim_whenAmountAboveClaim_reverts(type(uint128).max);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore maximum invalid seed");
        snapshot = vm.snapshotState();
        test_givenMaximumClaim_whenAmountAboveIdle_reverts(1, 0);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore minimum idle seed");
        snapshot = vm.snapshotState();
        test_givenMaximumClaim_whenAmountAboveIdle_reverts(
            type(uint128).max,
            type(uint128).max - 1
        );
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore maximum idle seed");
        test_givenClaim_whenWithdrawnToSelf(type(uint128).max, true);
    }

    // Scenarios: BLINV-WITHDRAW-L01, BLINV-WITHDRAW-L03.
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
