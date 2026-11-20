// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
// Interfaces
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";

// Libraries
import {EMERGENCY_ROLE, ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";
import {Actions, Kernel, KernelAdapter} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

contract BurnerLoansPayoutConfigTimelockChangeKernelTest is BurnerLoansPayoutConfigTimelockTest {
    // Scenarios: BLCUCT-KERNEL-A01, BLCUCT-KERNEL-I01, BLCUCT-KERNEL-I02, BLCUCT-KERNEL-I03.
    function test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges(
        address candidate_,
        bool active_,
        bool enabled_
    ) public givenPendingRecovery {
        _setState(_payoutTimelock, active_, enabled_);
        bytes32 queue = _queueDigest(_pendingId);
        uint48 last = _payoutTimelock.lastTransitionAt();
        uint32 grace = _payoutTimelock.gracePeriod();
        address roles = address(_payoutTimelock.ROLES());
        vm.prank(address(_kernel));
        _payoutTimelock.changeKernel(Kernel(candidate_));
        assertEq(address(_payoutTimelock.kernel()), candidate_, "Exact unvalidated pointer");
        assertEq(address(_payoutTimelock.ROLES()), roles, "No automatic module refresh");
        assertEq(address(_payoutTimelock.payout()), address(_payout), "Immutable Payout retained");
        assertEq(_payoutTimelock.isEnabled(), enabled_, "Enabled flag retained");
        assertEq(_payoutTimelock.lastTransitionAt(), last, "History retained");
        assertEq(_payoutTimelock.gracePeriod(), grace, "Grace retained");
        assertEq(_queueDigest(_pendingId), queue, "Queue metadata, guards and ownership retained");
    }

    // Scenarios: BLCUCT-KERNEL-A02.
    function test_givenOtherCaller_whenKernelChanged_reverts(
        address caller_,
        address candidate_,
        bool active_,
        bool enabled_
    ) public givenPendingRecovery {
        vm.assume(caller_ != address(_kernel));
        _setState(_payoutTimelock, active_, enabled_);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.changeKernel, (Kernel(candidate_))),
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_),
            caller_
        );
        assertEq(address(_payoutTimelock.kernel()), address(_kernel), "Pointer unchanged");
    }

    // Scenarios: BLCUCT-KERNEL-D01.
    function test_givenOnlyTimelockMigrated_whenUsed_thenBindingRejectedAndCancellationAvailable()
        public
        givenPendingRecovery
    {
        Kernel next = _newKernel();
        vm.prank(address(_kernel));
        _payoutTimelock.changeKernel(next);
        next.executeAction(Actions.ActivatePolicy, address(_payoutTimelock));
        bytes memory reason = abi.encodeWithSelector(
            PolicyDependency.PolicyDependency_KernelMismatch.selector,
            address(_payout),
            address(next),
            address(_kernel)
        );
        _expectQueueRejected(
            abi.encodeCall(_payoutTimelock.queueRescue, (address(_asset), _borrower)),
            reason,
            address(this)
        );
        bytes32 queue = _queueDigest(_pendingId);
        _makeReady(_pendingId);
        vm.expectRevert(reason);
        _payoutTimelock.executeQueuedAction(_pendingId);
        assertEq(_queueDigest(_pendingId), queue, "Migration mismatch preserves pending work");
        _payoutTimelock.cancelQueuedAction(_pendingId);
        _assertCleared(_pendingId, _single(_rescueAction()));
        _payoutTimelock.disable("");
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.enable, (bytes(""))),
            reason,
            address(this)
        );
        _expectLocalRejected(abi.encodeCall(_payoutTimelock.reEnable, ()), reason, address(this));
    }

    // Scenarios: BLCUCT-KERNEL-D02.
    function test_givenBothPoliciesMigrated_whenExecuted_thenOriginalTargetPays(
        address caller_
    ) public givenPendingRecovery {
        _asset.mint(address(_payout), 7);
        Kernel next = _newKernel();
        bytes32 queue = _queueDigest(_pendingId);
        vm.prank(address(_kernel));
        _payout.changeKernel(next);
        vm.prank(address(_kernel));
        _payoutTimelock.changeKernel(next);
        next.executeAction(Actions.ActivatePolicy, address(_payout));
        next.executeAction(Actions.ActivatePolicy, address(_payoutTimelock));
        assertEq(_queueDigest(_pendingId), queue, "Migration preserves recorded commitments");
        uint256 beforeBalance = _asset.balanceOf(_borrower);
        _makeReady(_pendingId);
        vm.prank(caller_);
        _payoutTimelock.executeQueuedAction(_pendingId);
        assertEq(_asset.balanceOf(_borrower), beforeBalance + 7, "Same concrete Payout pays");
        _assertCleared(_pendingId, _single(_rescueAction()));
    }

    function _newKernel() internal returns (Kernel next) {
        next = new Kernel();
        OlympusRoles roles = new OlympusRoles(next);
        next.executeAction(Actions.InstallModule, address(roles));
        next.executeAction(Actions.InstallModule, address(new OlympusTreasury(next)));
        RolesAdmin admin = new RolesAdmin(next);
        next.executeAction(Actions.ActivatePolicy, address(admin));
        admin.grantRole(ADMIN_ROLE, address(this));
        admin.grantRole(EMERGENCY_ROLE, address(this));
    }

    // Scenarios: BLCUCT-KERNEL-A01, BLCUCT-KERNEL-A02, BLCUCT-KERNEL-I01, BLCUCT-KERNEL-I02, BLCUCT-KERNEL-I03.
    function test_whenPointerBoundarySeedsUsed_thenOnlyPointerChanges() public {
        uint256 checkpoint = vm.snapshotState();
        Kernel next = new Kernel();
        for (uint256 a; a < 2; ++a)
            for (uint256 e; e < 2; ++e) {
                test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges(
                    address(next),
                    a != 0,
                    e != 0
                );
                _restore(checkpoint);
                test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges(
                    address(0),
                    a != 0,
                    e != 0
                );
                _restore(checkpoint);
                test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges(
                    address(0x1234),
                    a != 0,
                    e != 0
                );
                _restore(checkpoint);
                test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges(
                    address(_kernel),
                    a != 0,
                    e != 0
                );
                _restore(checkpoint);
                test_givenOtherCaller_whenKernelChanged_reverts(
                    address(0),
                    address(0),
                    a != 0,
                    e != 0
                );
                _restore(checkpoint);
            }
    }
}
