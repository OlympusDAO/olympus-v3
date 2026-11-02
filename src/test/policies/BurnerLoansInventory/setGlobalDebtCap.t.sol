// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

// Interfaces

import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";

// Libraries

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

// Shared domain values use constants; scenario-specific literals remain inline for auditability.

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.

contract BurnerLoansInventorySetGlobalDebtCapTest is BurnerLoansInventoryTest {
    function setUp() public override {
        super.setUp();
        _enableAndSetCap(200e9);
    }

    // Scenarios: BLINV-GLOBAL-CAP-N01.
    function test_givenPrincipal_whenInvalidCap_reverts(uint128 cap_) public {
        _draw(20e9);
        cap_ = uint128(bound(cap_, 0, 20e9 - 1));
        bytes32 beforeState = _accountingState();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InvalidCap.selector,
                cap_,
                20e9
            )
        );
        vm.prank(admin);
        inventory.setGlobalDebtCap(cap_);
        assertEq(inventory.globalDebtCapOhm(), 200e9, "Cap unchanged");
        assertEq(_accountingState(), beforeState, "Accounting unchanged");
    }

    // Scenarios: BLINV-GLOBAL-CAP-N02.
    function test_givenPrincipal_whenValidCapSet(uint128 cap_) public {
        _draw(20e9);
        cap_ = uint128(bound(cap_, 20e9 + 1, type(uint128).max));
        vm.assume(cap_ != 200e9);
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.GlobalDebtCapSet(cap_);
        vm.prank(admin);
        inventory.setGlobalDebtCap(cap_);
        assertEq(inventory.globalDebtCapOhm(), cap_, "New cap");
        assertEq(mintr.mintApproval(address(inventory)), uint256(cap_) - 20e9, "New approval");
        assertEq(inventory.activePrincipalOhm(), 20e9, "Principal unchanged");
        assertEq(ohm.balanceOf(recipient), 20e9, "No token movement");
        _assertInventoryInvariant();
    }

    // Scenarios: BLINV-GLOBAL-CAP-P02.
    function test_givenSameCapAndExcessApproval_whenSet_thenApprovalSynchronized(
        uint128 cap_
    ) public {
        vm.prank(admin);
        inventory.setGlobalDebtCap(cap_);
        bytes32 expectedState = _accountingState();
        vm.prank(address(inventory));
        mintr.increaseMintApproval(address(inventory), type(uint256).max);
        vm.expectEmit(address(mintr));
        emit MINTRv1.DecreaseMintApproval(address(inventory), cap_);
        vm.recordLogs();
        vm.prank(admin);
        inventory.setGlobalDebtCap(cap_);
        assertEq(vm.getRecordedLogs().length, 1, "Only approval synchronization emits an event");
        assertEq(inventory.globalDebtCapOhm(), cap_, "Same cap retained");
        assertEq(
            _accountingState(),
            expectedState,
            "Approval restored without other accounting changes"
        );
    }

    // Scenarios: BLINV-GLOBAL-CAP-P02.
    function test_givenSameCapAndInsufficientApproval_whenSet_thenApprovalSynchronized(
        uint128 cap_
    ) public {
        cap_ = uint128(bound(cap_, 1, type(uint128).max));
        vm.prank(admin);
        inventory.setGlobalDebtCap(cap_);
        bytes32 expectedState = _accountingState();
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), cap_);
        vm.expectEmit(address(mintr));
        emit MINTRv1.IncreaseMintApproval(address(inventory), cap_);
        vm.recordLogs();
        vm.prank(admin);
        inventory.setGlobalDebtCap(cap_);
        assertEq(vm.getRecordedLogs().length, 1, "Only approval synchronization emits an event");
        assertEq(
            _accountingState(),
            expectedState,
            "Approval restored without other accounting changes"
        );
    }

    // Scenarios: BLINV-GLOBAL-CAP-P02.
    function test_givenSameCapWithPrincipalIdleAndDonation_whenSet_thenApprovalSynchronized()
        public
    {
        _draw(20e9);
        _supply(50e9);
        ohm.mint(address(inventory), 30e9);
        bytes32 expectedState = _accountingState();
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), type(uint256).max);
        vm.prank(admin);
        inventory.setGlobalDebtCap(200e9);
        // 200 cap - 20 principal - 50 provider idle = 130 mint approval (all 9 decimals).
        // The 30 OHM donation is surplus and does not reduce the approval target.
        assertEq(
            mintr.mintApproval(address(inventory)),
            130e9,
            "Live principal and idle determine approval"
        );
        assertEq(
            _accountingState(),
            expectedState,
            "Synchronization preserves all claims and custody"
        );
    }

    // Scenarios: BLINV-GLOBAL-CAP-P09.
    function test_givenSameCapAndApprovalAligned_whenSet_thenNoWrites(uint128 cap_) public {
        vm.prank(admin);
        inventory.setGlobalDebtCap(cap_);
        bytes32 expectedState = _accountingState();
        vm.mockCallRevert(
            address(mintr),
            abi.encodeWithSelector(MINTRv1.increaseMintApproval.selector),
            abi.encodeWithSelector(ApprovalChangeFailed.selector)
        );
        vm.mockCallRevert(
            address(mintr),
            abi.encodeWithSelector(MINTRv1.decreaseMintApproval.selector),
            abi.encodeWithSelector(ApprovalChangeFailed.selector)
        );
        vm.recordLogs();
        vm.prank(admin);
        inventory.setGlobalDebtCap(cap_);
        assertEq(vm.getRecordedLogs().length, 0, "Aligned approval and cap emit no events");
        assertEq(_accountingState(), expectedState, "No accounting or approval changes");
    }

    // Scenarios: BLINV-GLOBAL-CAP-P10.
    function test_givenSameCapAndApprovalSyncFails_whenSet_reverts(
        uint128 cap_,
        bool excess_
    ) public {
        cap_ = uint128(bound(cap_, 1, type(uint128).max));
        vm.prank(admin);
        inventory.setGlobalDebtCap(cap_);
        vm.prank(address(inventory));
        if (excess_) mintr.increaseMintApproval(address(inventory), type(uint256).max);
        else mintr.decreaseMintApproval(address(inventory), cap_);
        bytes32 beforeState = _accountingState();
        vm.mockCallRevert(
            address(mintr),
            abi.encodeWithSelector(
                excess_
                    ? MINTRv1.decreaseMintApproval.selector
                    : MINTRv1.increaseMintApproval.selector
            ),
            abi.encodeWithSelector(ApprovalChangeFailed.selector)
        );
        vm.expectRevert(ApprovalChangeFailed.selector);
        vm.prank(admin);
        inventory.setGlobalDebtCap(cap_);
        assertEq(inventory.globalDebtCapOhm(), cap_, "Cap retained after failed synchronization");
        assertEq(
            _accountingState(),
            beforeState,
            "Failed synchronization preserves accounting and approval"
        );
    }

    error ApprovalChangeFailed();

    // Scenarios: BLINV-GLOBAL-CAP-P03.
    function test_givenIdleExceedsRoom_whenCapLowered() public {
        _draw(20e9);
        _supply(150e9);
        vm.prank(admin);
        inventory.setGlobalDebtCap(120e9);
        assertEq(mintr.mintApproval(address(inventory)), 0, "No mint room");
        assertEq(inventory.availableCapacity(), 100e9, "Capacity limited to cap less principal");
        assertEq(inventory.suppliedIdleOhm(), 150e9, "Idle not confiscated");
        assertEq(inventory.providerClaimOhm(provider), 150e9, "Provider claim retained");
        assertEq(ohm.balanceOf(address(inventory)), 150e9, "Custody untouched");
    }

    // Scenarios: BLINV-GLOBAL-CAP-P06.
    function test_givenDonationAndIdle_whenCapLowered() public {
        _draw(20e9);
        _supply(50e9);
        ohm.mint(address(inventory), 30e9);
        vm.prank(admin);
        inventory.setGlobalDebtCap(120e9);
        // 120 cap - 20 principal - 50 supplied idle = 50 mint approval (all 9 decimals).
        assertEq(
            mintr.mintApproval(address(inventory)),
            50e9,
            "Donation excluded from approval target"
        );
        assertEq(inventory.availableCapacity(), 100e9, "Idle plus approval");
        assertEq(inventory.surplusOhm(), 30e9, "Donation remains surplus");
        assertEq(inventory.suppliedOhm(), 50e9, "Provider obligation retained");
    }

    // Scenarios: BLINV-GLOBAL-CAP-L01, BLINV-GLOBAL-CAP-L02, BLINV-GLOBAL-CAP-L03, BLINV-GLOBAL-CAP-L04, BLINV-GLOBAL-CAP-N04.
    function test_givenCoreLifecycle_whenCapSet(bool active_, bool enabled_) public {
        _setPolicyActive(address(facility), active_);
        _mockFacilityEnabled(enabled_);
        vm.prank(admin);
        inventory.setGlobalDebtCap(1);
        assertEq(inventory.globalDebtCapOhm(), 1, "Independent ADMIN cap update");
        assertEq(mintr.mintApproval(address(inventory)), 1, "Exact approval");
    }

    // Scenarios: BLINV-GLOBAL-CAP-N01, BLINV-GLOBAL-CAP-N02, BLINV-GLOBAL-CAP-P02.
    function test_whenCapBoundarySeeds() public {
        uint128[3] memory invalidCaps = [uint128(0), 1, 20e9 - 1];
        for (uint256 i; i < invalidCaps.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            test_givenPrincipal_whenInvalidCap_reverts(invalidCaps[i]);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore invalid cap seed");
        }
        uint128[3] memory validCaps = [uint128(20e9 + 1), type(uint128).max - 1, type(uint128).max];
        for (uint256 i; i < validCaps.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            test_givenPrincipal_whenValidCapSet(validCaps[i]);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore valid cap seed");
        }
        uint256 snapshot = vm.snapshotState();
        test_givenSameCapAndExcessApproval_whenSet_thenApprovalSynchronized(0);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore zero cap seed");
        test_givenSameCapAndExcessApproval_whenSet_thenApprovalSynchronized(type(uint128).max);
        test_givenSameCapAndInsufficientApproval_whenSet_thenApprovalSynchronized(1);
        test_givenSameCapAndInsufficientApproval_whenSet_thenApprovalSynchronized(
            type(uint128).max
        );
    }

    // Scenarios: BLINV-GLOBAL-CAP-P01.
    function test_givenProviderIdle_whenExactPrincipalCapSet() public {
        _draw(20e9);
        _supply(50e9);
        vm.expectEmit(address(inventory));
        emit IBurnerLoansInventory.GlobalDebtCapSet(20e9);
        vm.prank(admin);
        inventory.setGlobalDebtCap(20e9);
        assertEq(mintr.mintApproval(address(inventory)), 0, "No room above principal floor");
        assertEq(inventory.providerClaimOhm(provider), 50e9, "Provider claim retained");
        assertEq(inventory.suppliedIdleOhm(), 50e9, "Provider idle retained");
        assertEq(ohm.balanceOf(address(inventory)), 50e9, "Provider custody retained");
    }

    // Scenarios: BLINV-GLOBAL-CAP-L01, BLINV-GLOBAL-CAP-L02, BLINV-GLOBAL-CAP-L03, BLINV-GLOBAL-CAP-L04, BLINV-GLOBAL-CAP-N04.
    function test_whenCoreLifecycleSeeds() public {
        for (uint8 flags; flags < 4; ++flags) {
            uint256 snapshot = vm.snapshotState();
            test_givenCoreLifecycle_whenCapSet(flags & 1 != 0, flags & 2 != 0);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore Core lifecycle seed");
        }
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
