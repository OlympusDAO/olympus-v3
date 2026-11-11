// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Bounded seed loops intentionally repeat isolated contract calls.
// Literal amounts, delays and timestamps are independent expected test values.
// Tests intentionally read state after calls to assert effects and rollback.
// Expected-revert calls and repeated configuration probes discard their return values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, reentrancy-no-eth, unused-return)

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";
import {Kernel, KernelAdapter, Actions} from "src/Kernel.sol";
import {toKeycode} from "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";

contract BurnerLoansInventoryConfigTimelockChangeKernelTest is
    BurnerLoansInventoryConfigTimelockTest
{
    // Scenarios: BLINCT-KERNEL-A01.
    function test_whenCallerIsNotCurrentKernel_reverts(
        address caller_
    ) public givenPendingRecovery {
        vm.assume(caller_ != address(_kernel));
        Kernel next = new Kernel();
        bytes32 state = _queueDigest(_pendingId);
        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        _timelock.changeKernel(next);
        assertEq(address(_timelock.kernel()), address(_kernel), "Unauthorized pointer unchanged");
        assertEq(_queueDigest(_pendingId), state, "Unauthorized migration preserves all state");
    }

    // Scenarios: BLINCT-KERNEL-A02, BLINCT-KERNEL-L01, BLINCT-KERNEL-L02, BLINCT-KERNEL-L03, BLINCT-KERNEL-L04, BLINCT-KERNEL-I01, BLINCT-KERNEL-I02, BLINCT-KERNEL-P01.
    function test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges(
        address next_,
        bool active_,
        bool enabled_
    ) public givenPendingRecovery {
        _setState(_timelock, active_, enabled_);
        bytes32 state = _queueDigest(_pendingId);
        uint48 last = _timelock.lastTransitionAt();
        uint32 grace = _timelock.gracePeriod();
        address cachedRoles = address(_timelock.ROLES());
        vm.recordLogs();
        vm.prank(address(_kernel));
        _timelock.changeKernel(Kernel(next_));
        assertEq(vm.getRecordedLogs().length, 0, "Pointer hook emits no event");
        assertEq(address(_timelock.ROLES()), cachedRoles, "Pointer hook preserves cached ROLES");
        assertEq(address(_timelock.kernel()), next_, "Exact pointer, including zero or unchanged");
        assertEq(
            address(_timelock.inventory()),
            address(_inventory),
            "Immutable Inventory preserved"
        );
        assertEq(_timelock.isEnabled(), enabled_, "Local flag preserved");
        assertEq(_timelock.lastTransitionAt(), last, "Transition history preserved");
        assertEq(_timelock.gracePeriod(), grace, "Grace preserved");
        assertEq(
            _queueDigest(_pendingId),
            state,
            "Pointer hook does not change queue, guards or funds"
        );
    }

    // Scenarios: BLINCT-KERNEL-A03.
    function test_givenKernelChanged_whenFormerKernelCalls_reverts() public givenPendingRecovery {
        Kernel next = new Kernel();
        vm.prank(address(_kernel));
        _timelock.changeKernel(next);
        bytes32 state = _queueDigest(_pendingId);
        vm.expectRevert(
            abi.encodeWithSelector(
                KernelAdapter.KernelAdapter_OnlyKernel.selector,
                address(_kernel)
            )
        );
        vm.prank(address(_kernel));
        _timelock.changeKernel(_kernel);
        assertEq(address(_timelock.kernel()), address(next), "Former Kernel loses authority");
        assertEq(_queueDigest(_pendingId), state, "Failed second migration preserves work");
    }

    // Scenarios: BLINCT-KERNEL-D01.
    function test_givenNewKernelNotActivated_whenExecuted_reverts(
        address caller_
    ) public givenPendingRecovery {
        Kernel next = new Kernel();
        vm.prank(address(_kernel));
        _timelock.changeKernel(next);
        _makeReady(_pendingId);
        assertFalse(_timelock.isActive(), "Membership follows current Kernel");
        bytes32 state = _queueDigest(_pendingId);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
        vm.prank(caller_);
        _timelock.executeQueuedAction(_pendingId);
        assertEq(_queueDigest(_pendingId), state, "Unactivated migration retains pending work");
    }

    // Scenarios: BLINCT-KERNEL-D02.
    function test_givenOnlyTimelockMigrated_whenExecuted_reverts(
        address caller_
    ) public givenPendingRecovery {
        Kernel next = _newKernel();
        vm.prank(address(_kernel));
        _timelock.changeKernel(next);
        next.executeAction(Actions.ActivatePolicy, address(_timelock));
        _makeReady(_pendingId);
        bytes32 state = _queueDigest(_pendingId);
        assertTrue(_timelock.isActive(), "Timelock admitted on new Kernel");
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_inventory),
                address(next),
                address(_kernel)
            )
        );
        vm.prank(caller_);
        _timelock.executeQueuedAction(_pendingId);
        assertEq(_queueDigest(_pendingId), state, "Target mismatch retains pending work");
    }

    // Scenarios: BLINCT-KERNEL-D03.
    function test_givenBothPoliciesMigrated_whenExecuted_thenOriginalRecoverySucceeds(
        address caller_
    ) public givenPendingRecovery {
        _ohm.mint(address(_inventory), 1e9);
        Kernel next = _newKernel();
        vm.prank(address(_kernel));
        _timelock.changeKernel(next);
        vm.prank(address(_kernel));
        _inventory.changeKernel(next);
        next.executeAction(Actions.ActivatePolicy, address(_timelock));
        next.executeAction(Actions.ActivatePolicy, address(_inventory));
        assertTrue(_timelock.isActive(), "Timelock active on destination Kernel");
        assertEq(
            address(_timelock.ROLES()),
            address(next.getModuleForKeycode(toKeycode("ROLES"))),
            "ROLES refreshed"
        );
        _makeReady(_pendingId);
        vm.prank(caller_);
        _timelock.executeQueuedAction(_pendingId);
        _assertCleared(_pendingId);
        assertEq(
            _ohm.balanceOf(address(next.getModuleForKeycode(toKeycode("TRSRY")))),
            1e9,
            "Immutable Inventory uses live migrated Treasury"
        );
    }

    function _newKernel() internal returns (Kernel next) {
        next = new Kernel();
        next.executeAction(Actions.InstallModule, address(new OlympusRoles(next)));
        next.executeAction(Actions.InstallModule, address(new OlympusMinter(next, address(_ohm))));
        next.executeAction(Actions.InstallModule, address(new OlympusTreasury(next)));
    }

    // Scenarios: BLINCT-KERNEL-A02, BLINCT-KERNEL-L01, BLINCT-KERNEL-L02, BLINCT-KERNEL-L03, BLINCT-KERNEL-L04.
    function test_givenEachLifecyclePair_whenMigrated_thenOnlyPointerChanges() public {
        Kernel next = new Kernel();
        uint256 checkpoint = vm.snapshotState();
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges(
                    address(next),
                    active != 0,
                    enabled != 0
                );
                _restore(checkpoint);
            }
        }
    }

    // Scenarios: BLINCT-KERNEL-I01.
    function test_whenNextKernelZero_thenOnlyPointerChanges() public {
        test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges(address(0), true, true);
        // Zero Kernel returns empty data; isActive cannot decode its framework response.
        vm.expectRevert(bytes(""));
        _timelock.isActive();
    }

    // Scenarios: BLINCT-KERNEL-I02.
    function test_whenNextKernelEOA_thenOnlyPointerChanges() public {
        test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges(address(0xabc1), true, true);
        // EOA has no framework ABI, so the response cannot be decoded.
        vm.expectRevert(bytes(""));
        _timelock.isActive();
    }

    // Scenarios: BLINCT-KERNEL-P01.
    function test_whenNextKernelUnchanged_thenNoOtherEffects() public {
        test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges(address(_kernel), true, true);
    }

    // Scenarios: BLINCT-KERNEL-A01.
    function test_givenAdminOrEmergency_whenKernelChanged_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenCallerIsNotCurrentKernel_reverts(address(this));
        _restore(checkpoint);
        _rolesAdmin.grantRole(EMERGENCY_ROLE, _recipient);
        test_whenCallerIsNotCurrentKernel_reverts(_recipient);
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, reentrancy-no-eth, unused-return)
