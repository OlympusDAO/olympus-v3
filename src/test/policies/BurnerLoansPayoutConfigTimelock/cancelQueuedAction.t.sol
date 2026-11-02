// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansPayoutConfigTimelockCancelQueuedActionTest is
    BurnerLoansPayoutConfigTimelockTest
{
    // Scenarios: BLCUCT-CANCEL-A01, BLCUCT-CANCEL-D01, BLCUCT-CANCEL-L01.
    function test_givenEmergencyCaller_whenCancelled_thenExactCleanup(
        address caller_,
        bool overlap_,
        uint48 now_
    ) public givenPendingRecovery {
        vm.assume(caller_ != address(0));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        if (overlap_) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        ITimelockBatchQueue.QueuedAction memory beforeAction = _payoutTimelock.getQueuedAction(
            _pendingId
        );
        uint64 unrelated = _payoutTimelock.queueSetSendFeesToDistributor(false);
        bytes32 other = _queueDigest(unrelated);
        bytes32 funds = _payoutDigest();
        // Leave representable notice/window room for the subsequent key-reuse proposal.
        vm.warp(bound(now_, 0, uint256(type(uint48).max) - 4 days));
        vm.expectEmit(address(_payoutTimelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(_pendingId, caller_);
        vm.prank(caller_);
        _payoutTimelock.cancelQueuedAction(_pendingId);
        ITimelockBatchQueue.QueuedAction memory afterAction = _payoutTimelock.getQueuedAction(
            _pendingId
        );
        assertTrue(afterAction.cancelled, "Cancelled");
        assertFalse(afterAction.executed, "Not executed");
        assertEq(afterAction.proposer, beforeAction.proposer, "Proposer retained");
        assertEq(afterAction.queuedAt, beforeAction.queuedAt, "Queue time retained");
        assertEq(afterAction.executableAt, beforeAction.executableAt, "Ready time retained");
        assertEq(afterAction.expiresAt, beforeAction.expiresAt, "Expiry retained");
        _assertCleared(_pendingId, beforeAction.actions);
        assertEq(_queueDigest(unrelated), other, "Unrelated action retained");
        assertEq(_payoutDigest(), funds, "No transfer or entitlement mutation");
        _removedGetters(
            _pendingId,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                _pendingId
            ),
            _borrower,
            0,
            0
        );
        uint64 replacement = _payoutTimelock.queueRescue(address(_asset), _borrower);
        assertEq(
            _payoutTimelock.pendingActionId(_scopedKey(_rescueAction())),
            replacement,
            "Released key reusable even after expiry"
        );
    }

    // Scenarios: BLCUCT-CANCEL-A02.
    function test_givenNoEmergencyRole_whenCancelled_reverts(
        address caller_
    ) public givenPendingRecovery {
        vm.assume(!_roles.hasRole(caller_, EMERGENCY_ROLE));
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.cancelQueuedAction, (_pendingId)),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE),
            caller_
        );
    }

    // Scenarios: BLCUCT-CANCEL-L02.
    function test_givenActiveDisabled_whenCancelled_reverts(
        address caller_
    ) public givenPendingRecovery {
        _setState(_payoutTimelock, true, false);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.cancelQueuedAction, (_pendingId)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            caller_
        );
    }

    // Scenarios: BLCUCT-CANCEL-L04.
    function test_givenInactiveDisabled_whenCancelled_reverts(
        address caller_
    ) public givenPendingRecovery {
        _setState(_payoutTimelock, false, false);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.cancelQueuedAction, (_pendingId)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-CANCEL-L03.
    function test_givenInactiveEnabled_whenCancelled_reverts(
        address caller_
    ) public givenPendingRecovery {
        _setState(_payoutTimelock, false, true);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.cancelQueuedAction, (_pendingId)),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-CANCEL-I01.
    function test_whenUnknownIdCancelled_reverts(address caller_, uint64 id_) public {
        bytes memory reason = abi.encodeWithSelector(
            ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
            id_
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _payoutTimelock.cancelQueuedAction(id_);
        vm.expectRevert(reason);
        vm.prank(caller_);
        _payoutTimelock.getQueuedAction(id_);
        _removedGetters(id_, reason, caller_, 0, 0);
    }

    // Scenarios: BLCUCT-CANCEL-I02.
    function test_givenExecuted_whenCancelled_reverts(address caller_) public givenPendingRecovery {
        _makeReady(_pendingId);
        _payoutTimelock.executeQueuedAction(_pendingId);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.cancelQueuedAction, (_pendingId)),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                _pendingId
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-CANCEL-I03.
    function test_givenCancelled_whenCancelled_reverts(
        address caller_
    ) public givenPendingRecovery {
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(this));
        _payoutTimelock.cancelQueuedAction(_pendingId);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.cancelQueuedAction, (_pendingId)),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                _pendingId
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-CANCEL-D02.
    function test_givenBrokenRetiredTarget_whenCancelled_thenNoTargetReads(
        address caller_
    ) public givenPendingRecovery {
        vm.assume(caller_ != address(0));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        _payout.setConfigOperator(_recipient);
        _setState(_payout, false, false);
        _rejectTargetReads();
        vm.prank(caller_);
        _payoutTimelock.cancelQueuedAction(_pendingId);
        _assertCleared(_pendingId, _single(_rescueAction()));
    }

    // Scenarios: BLCUCT-CANCEL-A01, BLCUCT-CANCEL-A02, BLCUCT-CANCEL-D01, BLCUCT-CANCEL-I01.
    function test_whenCancellationBoundarySeedsUsed() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenUnknownIdCancelled_reverts(address(0), 0);
        _restore(checkpoint);
        test_whenUnknownIdCancelled_reverts(_borrower, type(uint64).max);
        _restore(checkpoint);
        test_givenEmergencyCaller_whenCancelled_thenExactCleanup(address(0x111), false, 1);
        _restore(checkpoint);
        test_givenEmergencyCaller_whenCancelled_thenExactCleanup(address(0x112), true, 1 days + 1);
        _restore(checkpoint);
        test_givenEmergencyCaller_whenCancelled_thenExactCleanup(address(0x113), false, 4 days + 2);
        _restore(checkpoint);
        test_givenNoEmergencyRole_whenCancelled_reverts(address(this));
        _restore(checkpoint);
        test_givenNoEmergencyRole_whenCancelled_reverts(_recipient);
        _restore(checkpoint);
        test_givenNoEmergencyRole_whenCancelled_reverts(_borrower);
        _restore(checkpoint);

        vm.prank(_recipient);
        _pendingId = _payoutTimelock.queueRescue(address(_asset), _borrower);
        _rolesAdmin.revokeRole(BURNER_LOANS_ADMIN_ROLE, _recipient);
        _expectLocalRejected(
            abi.encodeCall(_payoutTimelock.cancelQueuedAction, (_pendingId)),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE),
            _recipient
        );
        _restore(checkpoint);
    }
}
