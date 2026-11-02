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
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryDisableTest is BurnerLoansInventoryTest {
    // Scenarios: BLINV-DISABLE-A01, BLINV-DISABLE-L03, BLINV-DISABLE-L04, BLINV-DISABLE-L05, BLINV-DISABLE-L06, BLINV-DISABLE-L07, BLINV-DISABLE-L08, BLINV-DISABLE-L09, BLINV-DISABLE-L10.
    function test_givenLifecycle_whenAuthorizedCallerDisables(
        address caller_,
        uint8 roles_,
        bool active_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _grantTransitionCaller(caller_, roles_, EMERGENCY_ROLE);
        _enableAndSetCap(DEFAULT_CAP);
        _supply(100);
        _draw(40);
        if (!active_) _deactivateInventory();
        _setPolicyActive(address(facility), coreActive_);
        _mockFacilityEnabled(coreEnabled_);
        bytes32 beforeState = _accountingState();
        uint48 disabledAt = uint48(vm.getBlockTimestamp() + 10);
        vm.warp(disabledAt);
        vm.expectEmit(address(inventory));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(inventory));
        emit IEnablerV2.Transition(caller_, false, "", disabledAt);
        vm.prank(caller_);
        inventory.disable("");
        assertFalse(inventory.isEnabled(), "Inventory paused");
        assertEq(inventory.lastTransitionAt(), disabledAt, "Disable timestamp");
        assertEq(inventory.gracePeriod(), 7 days, "Grace unchanged");
        assertEq(_accountingState(), beforeState, "Custody and obligations preserved");
    }

    // Scenarios: BLINV-DISABLE-D01.
    function test_givenForeignCoreKernel_whenDisabled_succeeds() public {
        _initializeAndEnable();
        _mockFacilityKernel(outsider);
        vm.prank(admin);
        inventory.disable("");
        assertFalse(inventory.isEnabled(), "Broken service cannot block pause");
    }

    // Scenarios: BLINV-DISABLE-A03, BLINV-DISABLE-I04.
    function test_whenUnauthorizedCaller_reverts(address caller_, bytes memory data_) public {
        vm.assume(caller_ != admin && caller_ != emergency);
        _initializeAndEnable();
        bytes32 beforeState = _accountingState();
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.disable(data_);
        assertTrue(inventory.isEnabled(), "Still enabled");
        assertEq(_accountingState(), beforeState, "Accounting unchanged");
    }

    // Scenarios: BLINV-DISABLE-I03, BLINV-DISABLE-L01, BLINV-DISABLE-L02.
    function test_givenDisabled_whenDisabled_reverts(
        address caller_,
        bool active_,
        bytes memory data_
    ) public {
        if (!active_) _deactivateInventory();
        _expectNotEnabled();
        vm.prank(caller_);
        inventory.disable(data_);
        assertFalse(inventory.isEnabled(), "Still disabled");
        assertEq(inventory.lastTransitionAt(), 0, "No transition");
    }

    // Scenarios: BLINV-DISABLE-I01.
    function test_whenNonemptyPayload_reverts(
        uint256 length_,
        address caller_,
        uint8 roles_
    ) public {
        _grantTransitionCaller(caller_, roles_, EMERGENCY_ROLE);
        _initializeAndEnable();
        bytes32 beforeState = _accountingState();
        bytes memory data = new bytes(bound(length_, 1, 256));
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(caller_);
        inventory.disable(data);
        assertTrue(inventory.isEnabled(), "Still enabled");
        assertEq(_accountingState(), beforeState, "Accounting unchanged");
    }

    // Scenarios: BLINV-DISABLE-L11.
    function test_givenNeverConfigured_whenDisabled_reverts(address caller_) public {
        inventory = _newInventory();
        _expectNotEnabled();
        vm.prank(caller_);
        inventory.disable("");
        assertFalse(inventory.isEnabled(), "Never configured remains disabled");
        assertEq(inventory.lastTransitionAt(), 0, "No transition");
    }

    // Scenarios: BLINV-DISABLE-A01, BLINV-DISABLE-I01, BLINV-DISABLE-L03, BLINV-DISABLE-L04, BLINV-DISABLE-L05, BLINV-DISABLE-L06, BLINV-DISABLE-L07, BLINV-DISABLE-L08, BLINV-DISABLE-L09, BLINV-DISABLE-L10.
    function test_whenRoleAndLifecycleBoundarySeeds() public {
        for (uint8 role; role < 3; ++role) {
            for (uint8 flags; flags < 8; ++flags) {
                uint256 snapshot = vm.snapshotState();
                test_givenLifecycle_whenAuthorizedCallerDisables(
                    outsider,
                    role,
                    flags & 1 != 0,
                    flags & 2 != 0,
                    flags & 4 != 0
                );
                assertTrue(vm.revertToStateAndDelete(snapshot), "Restore seed fixture");
            }
            test_whenNonemptyPayload_reverts(1, outsider, role);
            test_whenNonemptyPayload_reverts(32, outsider, role);
            test_whenNonemptyPayload_reverts(256, outsider, role);
        }
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(admin);
        inventory.disable(hex"01");
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
