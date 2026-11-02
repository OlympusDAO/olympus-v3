// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryReEnableTest is BurnerLoansInventoryTest {
    function _disableAt(uint48 timestamp_, uint32 grace_) internal {
        vm.warp(timestamp_);
        if (!inventory.isEnabled()) _enableAndSetCap(DEFAULT_CAP);
        vm.prank(admin);
        inventory.setGracePeriod(grace_);
        _disableInventory();
    }

    function _disableWithinGrace(uint48 last_, uint32 grace_, uint48 now_) internal {
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, uint256(type(uint48).max) - grace_));
        _disableAt(last_, grace_);
        vm.warp(bound(now_, last_, uint256(last_) + grace_));
    }

    function _assertReEnable(address caller_) internal {
        bytes32 beforeState = _accountingState();
        uint32 grace = inventory.gracePeriod();
        vm.expectEmit(address(inventory));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(inventory));
        emit IEnablerV2.Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
        vm.prank(caller_);
        inventory.reEnable();
        assertTrue(inventory.isEnabled(), "Inventory re-enabled");
        assertEq(inventory.lastTransitionAt(), vm.getBlockTimestamp(), "Transition timestamp");
        assertEq(inventory.gracePeriod(), grace, "Grace unchanged");
        assertEq(inventory.globalDebtCapOhm(), DEFAULT_CAP, "Cap preserved");
        assertEq(_accountingState(), beforeState, "Accounting preserved");
    }

    // Scenarios: BLINV-REENABLE-P01, BLINV-REENABLE-P02.
    function test_givenValidGrace_whenReEnabled(
        uint48 last_,
        uint32 grace_,
        uint48 now_,
        address caller_,
        uint8 roles_,
        bool deadline_
    ) public {
        _grantTransitionCaller(caller_, roles_, BURNER_LOANS_ADMIN_ROLE);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, uint256(type(uint48).max) - grace_));
        _disableAt(last_, grace_);
        uint48 deadline = last_ + grace_;
        vm.warp(deadline_ ? deadline : bound(now_, last_, deadline - 1));
        _assertReEnable(caller_);
    }

    // Scenarios: BLINV-REENABLE-P03.
    function test_givenExpiredGrace_whenReEnabled_reverts(
        uint48 last_,
        uint32 grace_,
        uint48 now_,
        address caller_,
        uint8 roles_
    ) public {
        _grantTransitionCaller(caller_, roles_, BURNER_LOANS_ADMIN_ROLE);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, uint256(type(uint48).max) - grace_ - 1));
        _disableAt(last_, grace_);
        uint48 deadline = last_ + grace_;
        vm.warp(bound(now_, uint256(deadline) + 1, type(uint48).max));
        bytes32 beforeState = _accountingState();
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        inventory.reEnable();
        assertFalse(inventory.isEnabled(), "Still paused");
        assertEq(inventory.lastTransitionAt(), last_, "No transition");
        assertEq(_accountingState(), beforeState, "Accounting preserved");
    }

    // Scenarios: BLINV-REENABLE-N01.
    function test_givenUnrepresentableDeadline_whenReEnabled_reverts(
        uint48 last_,
        uint32 grace_,
        address caller_,
        uint8 roles_
    ) public {
        _grantTransitionCaller(caller_, roles_, BURNER_LOANS_ADMIN_ROLE);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, uint256(type(uint48).max) - grace_ + 1, type(uint48).max));
        _disableAt(last_, grace_);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(last_) + grace_
            )
        );
        vm.prank(caller_);
        inventory.reEnable();
        assertFalse(inventory.isEnabled(), "Still paused");
        assertEq(inventory.lastTransitionAt(), last_, "No transition");
    }

    // Scenarios: BLINV-REENABLE-D01, BLINV-REENABLE-D02, BLINV-REENABLE-D03.
    function test_givenDependencyLifecycle_whenReEnabled(
        address caller_,
        uint8 roles_,
        bool active_,
        bool enabled_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public {
        _grantTransitionCaller(caller_, roles_, BURNER_LOANS_ADMIN_ROLE);
        _disableWithinGrace(last_, grace_, now_);
        _setPolicyActive(address(facility), active_);
        _mockFacilityEnabled(enabled_);
        _assertReEnable(caller_);
    }

    // Scenarios: BLINV-REENABLE-D04.
    function test_givenForeignCoreKernel_whenReEnabled_reverts(
        address caller_,
        uint8 roles_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public {
        _grantTransitionCaller(caller_, roles_, BURNER_LOANS_ADMIN_ROLE);
        _disableWithinGrace(last_, grace_, now_);
        _mockFacilityKernel(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(facility),
                address(kernel),
                outsider
            )
        );
        vm.prank(caller_);
        inventory.reEnable();
        assertFalse(inventory.isEnabled(), "Still paused");
        assertLe(inventory.lastTransitionAt(), block.timestamp, "No new transition");
        vm.clearMockedCalls();
        _assertReEnable(caller_);
    }

    // Scenarios: BLINV-REENABLE-L03.
    function test_givenInactiveInventory_whenReEnabled_reverts(
        address caller_,
        uint8 roles_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public {
        _grantTransitionCaller(caller_, roles_, BURNER_LOANS_ADMIN_ROLE);
        _disableWithinGrace(last_, grace_, now_);
        _deactivateInventory();
        _expectInventoryNotActive();
        vm.prank(caller_);
        inventory.reEnable();
        assertFalse(inventory.isEnabled(), "Still paused");
        _reactivateInventory();
        _assertReEnable(caller_);
    }

    // Scenarios: BLINV-REENABLE-A01, BLINV-REENABLE-A02.
    function test_whenUnauthorizedCaller_reverts(address caller_, bool expired_) public {
        vm.assume(caller_ != admin && caller_ != burnerLoansAdmin);
        _disableAt(1000, 7 days);
        if (expired_) {
            vm.warp(1000 + 7 days + 1);
            _mockFacilityKernel(outsider);
        }
        _expectNotAuthorised();
        vm.prank(caller_);
        inventory.reEnable();
        assertFalse(inventory.isEnabled(), "Still paused");
        assertEq(inventory.lastTransitionAt(), 1000, "No transition");
    }

    function _assertNeverEnabled(address caller_) internal {
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        inventory.reEnable();
        assertEq(inventory.lastTransitionAt(), 0, "Never enabled");
    }

    // Scenarios: BLINV-REENABLE-L02.
    function test_givenConfiguredNeverEnabled_whenReEnabled_reverts(
        address caller_,
        bool active_
    ) public {
        _setPolicyActive(address(inventory), active_);
        _assertNeverEnabled(caller_);
    }

    // Scenarios: BLINV-REENABLE-L04.
    function test_givenNeverConfigured_whenReEnabled_reverts(address caller_) public {
        inventory = _newInventory();
        _assertNeverEnabled(caller_);
    }

    // Scenarios: BLINV-REENABLE-L01.
    function test_givenAlreadyEnabled_whenReEnabled_reverts(
        address caller_,
        bool active_,
        bool zeroTimestamp_
    ) public {
        vm.warp(zeroTimestamp_ ? 0 : 1);
        _initializeAndEnable();
        if (!active_) _deactivateInventory();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        inventory.reEnable();
        assertTrue(inventory.isEnabled(), "Still enabled");
    }

    // Scenarios: BLINV-REENABLE-N01, BLINV-REENABLE-P01, BLINV-REENABLE-P02, BLINV-REENABLE-P03.
    function test_whenGraceAndRoleBoundarySeeds() public {
        for (uint8 role; role < 3; ++role) {
            for (uint8 seed; seed < 5; ++seed) {
                uint256 snapshot = vm.snapshotState();
                uint32 grace = seed < 2 ? 1 : type(uint32).max;
                uint48 last = seed == 4 ? type(uint48).max - grace : 1;
                test_givenValidGrace_whenReEnabled(
                    last,
                    grace,
                    seed % 3 == 1 ? last + grace - 1 : last,
                    outsider,
                    role,
                    seed % 3 == 0
                );
                assertTrue(vm.revertToStateAndDelete(snapshot), "Restore valid seed");
            }
            uint256 snapshot = vm.snapshotState();
            test_givenExpiredGrace_whenReEnabled_reverts(1, 1, 3, outsider, role);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore expired seed");
            snapshot = vm.snapshotState();
            test_givenExpiredGrace_whenReEnabled_reverts(
                1,
                type(uint32).max,
                type(uint48).max,
                outsider,
                role
            );
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore maximum seed");
            snapshot = vm.snapshotState();
            test_givenUnrepresentableDeadline_whenReEnabled_reverts(
                type(uint48).max,
                1,
                outsider,
                role
            );
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore overflow seed");
        }
    }

    // Scenarios: BLINV-REENABLE-D01, BLINV-REENABLE-D02, BLINV-REENABLE-D03, BLINV-REENABLE-D04, BLINV-REENABLE-L03.
    function test_whenDependencyAndRoleBoundarySeeds() public {
        for (uint8 role; role < 3; ++role) {
            for (uint8 flags; flags < 4; ++flags) {
                uint256 snapshot = vm.snapshotState();
                test_givenDependencyLifecycle_whenReEnabled(
                    outsider,
                    role,
                    flags & 1 != 0,
                    flags & 2 != 0,
                    1,
                    1,
                    2
                );
                assertTrue(vm.revertToStateAndDelete(snapshot), "Restore dependency seed");
            }
            uint256 snapshot = vm.snapshotState();
            test_givenForeignCoreKernel_whenReEnabled_reverts(
                outsider,
                role,
                1,
                type(uint32).max,
                2
            );
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore binding seed");
            snapshot = vm.snapshotState();
            test_givenInactiveInventory_whenReEnabled_reverts(
                outsider,
                role,
                1,
                type(uint32).max,
                2
            );
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore activity seed");
        }
    }
}

// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
