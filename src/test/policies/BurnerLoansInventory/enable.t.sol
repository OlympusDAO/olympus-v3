// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryEnableTest is BurnerLoansInventoryTest {
    // Scenarios: BLINV-ENABLE-A01.
    function test_givenNoConfigurator_succeeds() public {
        bytes32 beforeState = _accountingState();
        vm.expectEmit(address(inventory));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(inventory));
        emit IEnablerV2.Transition(admin, true, "", uint48(vm.getBlockTimestamp()));
        vm.prank(admin);
        inventory.enable("");
        assertTrue(inventory.isEnabled(), "Inventory enabled");
        assertEq(inventory.lastTransitionAt(), vm.getBlockTimestamp(), "Transition timestamp");
        assertEq(inventory.gracePeriod(), 7 days, "Grace unchanged");
        assertEq(_accountingState(), beforeState, "Accounting preserved");
    }

    // Scenarios: BLINV-ENABLE-D01, BLINV-ENABLE-D02, BLINV-ENABLE-D03.
    function test_givenFacilityLifecycle_whenEnabled(bool active_, bool enabled_) public {
        _setPolicyActive(address(facility), active_);
        // Core's enabled view is deliberately outside Inventory's dependency graph.
        _mockFacilityEnabled(enabled_);
        test_givenNoConfigurator_succeeds();
    }

    // Scenarios: BLINV-ENABLE-D04.
    function test_givenFacilityReportsDifferentKernel_reverts() public {
        bytes32 beforeState = _accountingState();
        _mockFacilityKernel(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(facility),
                address(kernel),
                outsider
            )
        );
        vm.prank(admin);
        inventory.enable("");
        assertFalse(inventory.isEnabled(), "Still disabled");
        assertEq(inventory.lastTransitionAt(), 0, "No transition");
        assertEq(_accountingState(), beforeState, "Accounting preserved");
        vm.clearMockedCalls();
        test_givenNoConfigurator_succeeds();
    }

    // Scenarios: BLINV-ENABLE-L02.
    function test_givenInactiveInventory_whenEnabled_reverts() public {
        _deactivateInventory();
        _expectInventoryNotActive();
        vm.prank(admin);
        inventory.enable("");
        assertFalse(inventory.isEnabled(), "Still disabled");
        assertEq(inventory.lastTransitionAt(), 0, "No transition");
        _reactivateInventory();
        test_givenNoConfigurator_succeeds();
    }

    // Scenarios: BLINV-ENABLE-A02, BLINV-ENABLE-I03.
    function test_whenCallerIsUnauthorized_reverts(address caller_, bytes memory data_) public {
        vm.assume(caller_ != admin);
        _expectAdminRole();
        vm.prank(caller_);
        inventory.enable(data_);
        assertFalse(inventory.isEnabled(), "Still disabled");
        assertEq(inventory.lastTransitionAt(), 0, "No transition");
    }

    // Scenarios: BLINV-ENABLE-I01.
    function test_whenPayloadIsNonempty_reverts(uint256 length_) public {
        bytes memory data = new bytes(bound(length_, 1, 256));
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(admin);
        inventory.enable(data);
        assertFalse(inventory.isEnabled(), "Still disabled");
        assertEq(inventory.lastTransitionAt(), 0, "No transition");
    }

    // Scenarios: BLINV-ENABLE-I01.
    function test_whenPayloadBoundarySeeds_revert() public {
        test_whenPayloadIsNonempty_reverts(1);
        test_whenPayloadIsNonempty_reverts(32);
        test_whenPayloadIsNonempty_reverts(256);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(admin);
        inventory.enable(hex"01");
    }

    // Scenarios: BLINV-ENABLE-I02, BLINV-ENABLE-L01.
    function test_givenAlreadyEnabled_whenEnabled_reverts(
        address caller_,
        bool active_,
        bytes memory data_
    ) public {
        _initializeAndEnable();
        if (!active_) _deactivateInventory();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        inventory.enable(data_);
        assertTrue(inventory.isEnabled(), "Still enabled");
    }

    // Scenarios: BLINV-ENABLE-L03.
    function test_givenUnconfiguredInventory_whenEnabled_reverts(address caller_) public {
        inventory = _newInventory();
        // A never-configured ROLES pointer returns no ABI boolean, hence exact empty revert.
        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        inventory.enable("");
        assertFalse(inventory.isEnabled(), "Still disabled");
        assertEq(inventory.lastTransitionAt(), 0, "No transition");
    }

    // Scenarios: BLINV-ENABLE-D01, BLINV-ENABLE-D02, BLINV-ENABLE-D03.
    function test_whenCoreLifecycleSeeds() public {
        for (uint8 flags; flags < 4; ++flags) {
            uint256 snapshot = vm.snapshotState();
            test_givenFacilityLifecycle_whenEnabled(flags & 1 != 0, flags & 2 != 0);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore Core lifecycle seed");
        }
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
