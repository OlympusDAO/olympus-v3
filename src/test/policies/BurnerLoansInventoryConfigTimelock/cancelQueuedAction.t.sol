// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts, delays and timestamps are independent expected test values.
// Tests intentionally read state after calls to assert effects and rollback.
// Expected-revert calls and repeated configuration probes discard their return values.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth, unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansInventoryConfigTimelockCancelQueuedActionTest is
    BurnerLoansInventoryConfigTimelockTest
{
    // Scenarios: BLINCT-CANCEL-A01, BLINCT-CANCEL-N01, BLINCT-CANCEL-N02, BLINCT-CANCEL-N03.
    function test_givenPendingAction_whenEmergencyCancels_thenExactCleanup(
        address caller_,
        uint48 now_
    ) public givenProviderSurplus givenPendingRecovery {
        vm.assume(caller_ != address(0));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        ITimelockBatchQueue.QueuedAction memory beforeAction = _timelock.getQueuedAction(
            _pendingId
        );
        now_ = SafeCast.toUint48(bound(now_, beforeAction.queuedAt, type(uint48).max));
        vm.warp(now_);
        bytes32 funds = _inventoryDigest();
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionCancelled(_pendingId, caller_);
        vm.prank(caller_);
        _timelock.cancelQueuedAction(_pendingId);
        ITimelockBatchQueue.QueuedAction memory afterAction = _timelock.getQueuedAction(_pendingId);
        assertTrue(afterAction.cancelled, "Cancellation recorded");
        assertFalse(afterAction.executed, "No execution occurred");
        assertEq(afterAction.proposer, beforeAction.proposer, "Proposer retained");
        assertEq(afterAction.queuedAt, beforeAction.queuedAt, "Queue time retained");
        assertEq(afterAction.executableAt, beforeAction.executableAt, "Notice retained");
        assertEq(afterAction.expiresAt, beforeAction.expiresAt, "Expiry retained");
        _assertCleared(_pendingId);
        assertEq(_inventoryDigest(), funds, "Cancellation moves no funds or claims");
    }

    // Scenarios: BLINCT-CANCEL-A02.
    function test_whenCallerLacksEmergency_reverts(address caller_) public givenPendingRecovery {
        vm.assume(!_roles.hasRole(caller_, EMERGENCY_ROLE));
        _expectCancelRejected(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, EMERGENCY_ROLE),
            caller_
        );
    }

    // Scenarios: BLINCT-CANCEL-L01.
    function test_givenActiveDisabledTimelock_whenCancelled_thenExactCleanup()
        public
        givenPendingRecovery
    {
        _rolesAdmin.grantRole(EMERGENCY_ROLE, _recipient);
        _setState(_timelock, true, false);
        bytes32 funds = _inventoryDigest();
        vm.prank(_recipient);
        _timelock.cancelQueuedAction(_pendingId);
        assertTrue(_timelock.getQueuedAction(_pendingId).cancelled, "Paused cancellation recorded");
        _assertCleared(_pendingId);
        assertEq(_inventoryDigest(), funds, "Cancellation preserves Inventory funds");
    }

    // Scenarios: BLINCT-CANCEL-L03.
    function test_givenInactiveDisabledTimelock_whenCancelled_reverts()
        public
        givenPendingRecovery
    {
        _rolesAdmin.grantRole(EMERGENCY_ROLE, _recipient);
        _setState(_timelock, false, false);
        _expectCancelRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            ),
            _recipient
        );
    }

    // Scenarios: BLINCT-CANCEL-L02.
    function test_givenInactiveTimelock_whenCancelled_reverts() public givenPendingRecovery {
        _rolesAdmin.grantRole(EMERGENCY_ROLE, _recipient);
        _setState(_timelock, false, true);
        _expectCancelRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            ),
            _recipient
        );
    }

    // Scenarios: BLINCT-CANCEL-P01.
    function test_givenCancelledAction_whenRecoveryRequeued_thenFreshIdOwnsKey()
        public
        givenPendingRecovery
    {
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(this));
        _timelock.cancelQueuedAction(_pendingId);
        uint64 id = _timelock.queueBurnSurplus();
        assertEq(id, uint256(_pendingId) + 1, "Fresh ID after cancellation");
        _assertQueued(id, IBurnerLoansInventory.burnSurplus.selector, address(this));
        assertTrue(_timelock.getQueuedAction(_pendingId).cancelled, "Old tombstone retained");
    }

    function _expectCancelRejected(bytes memory reason_, address caller_) internal {
        bytes32 state = _queueDigest(_pendingId);
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _timelock.cancelQueuedAction(_pendingId);
        assertEq(
            _queueDigest(_pendingId),
            state,
            "Failed cancellation preserves payload, guards, key and Inventory funds"
        );
    }

    // Scenarios: BLINCT-CANCEL-D01.
    function test_givenInactiveInventory_whenCancelled_thenNoReadinessCalls(
        bool enabled_
    ) public givenProviderSurplus givenPendingRecovery {
        _setState(_inventory, false, true);
        if (!enabled_) _timelock.disable("");
        _cancelWithoutReadiness();
    }

    // Scenarios: BLINCT-CANCEL-D02.
    function test_givenPausedInventory_whenCancelled_thenNoReadinessCalls(
        bool enabled_
    ) public givenProviderSurplus givenPendingRecovery {
        _inventory.disable("");
        if (!enabled_) _timelock.disable("");
        _cancelWithoutReadiness();
    }

    // Scenarios: BLINCT-CANCEL-D03.
    function test_givenInventoryKernelMismatch_whenCancelled_thenNoReadinessCalls(
        bool enabled_
    ) public givenProviderSurplus givenPendingRecovery {
        _mockInventoryKernel(address(0xbeef));
        if (!enabled_) _timelock.disable("");
        _cancelWithoutReadiness();
    }

    // Scenarios: BLINCT-CANCEL-D04.
    function test_givenControllerReplaced_whenCancelled_thenNoReadinessCalls(
        bool enabled_
    ) public givenProviderSurplus givenPendingRecovery {
        _inventory.setConfigOperator(_inventoryConfigurator);
        if (!enabled_) _timelock.disable("");
        _cancelWithoutReadiness();
    }

    // Scenarios: BLINCT-CANCEL-I01.
    function test_whenActionUnknown_revertsBeforeAuthorization(
        uint64 id_,
        address caller_
    ) public givenPendingRecovery {
        vm.assume(id_ != _pendingId);
        bytes32 state = _queueDigest(_pendingId);
        bytes memory reason = abi.encodeWithSelector(
            ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
            id_
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _timelock.cancelQueuedAction(id_);
        vm.expectRevert(reason);
        vm.prank(caller_);
        _timelock.getQueuedAction(id_);
        _assertTerminalGetters(id_, reason, caller_);
        assertEq(_queueDigest(_pendingId), state, "Unknown ID has no side effects");
    }

    // Scenarios: BLINCT-CANCEL-I02.
    function test_givenExecutedAction_whenCalled_revertsBeforeAuthorization(
        address caller_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _timelock.executeQueuedAction(_pendingId);
        bytes32 funds = _inventoryDigest();
        bytes memory reason = abi.encodeWithSelector(
            ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
            _pendingId
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _timelock.cancelQueuedAction(_pendingId);
        _assertTerminalGetters(_pendingId, reason, caller_);
        _assertCleared(_pendingId);
        assertEq(_inventoryDigest(), funds, "Terminal replay performs no second dispatch");
    }

    // Scenarios: BLINCT-CANCEL-I03.
    function test_givenCancelledAction_whenCalled_revertsBeforeAuthorization(
        address caller_
    ) public givenPendingRecovery {
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(this));
        _timelock.cancelQueuedAction(_pendingId);
        bytes32 funds = _inventoryDigest();
        bytes memory reason = abi.encodeWithSelector(
            ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
            _pendingId
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _timelock.cancelQueuedAction(_pendingId);
        _assertTerminalGetters(_pendingId, reason, caller_);
        _assertCleared(_pendingId);
        assertEq(_inventoryDigest(), funds, "Terminal replay performs no second dispatch");
    }

    // Scenarios: BLINCT-CANCEL-A01, BLINCT-CANCEL-N01.
    function test_givenNoticePeriod_whenCancelled_thenExactCleanup(
        uint48 now_,
        address caller_
    ) public {
        now_ = SafeCast.toUint48(
            bound(now_, vm.getBlockTimestamp(), vm.getBlockTimestamp() + 1 days - 1)
        );
        test_givenPendingAction_whenEmergencyCancels_thenExactCleanup(caller_, now_);
    }

    // Scenarios: BLINCT-CANCEL-A01, BLINCT-CANCEL-N03.
    function test_givenExpiredWindow_whenCancelled_thenExactCleanup(
        uint48 now_,
        address caller_
    ) public {
        now_ = SafeCast.toUint48(
            bound(now_, vm.getBlockTimestamp() + 4 days + 1, type(uint48).max)
        );
        test_givenPendingAction_whenEmergencyCancels_thenExactCleanup(caller_, now_);
    }

    // Scenarios: BLINCT-CANCEL-A01, BLINCT-CANCEL-N01, BLINCT-CANCEL-N02, BLINCT-CANCEL-N03.
    function test_givenCancellationTimeEndpointSeeds_whenCancelled_thenExactCleanup() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPendingAction_whenEmergencyCancels_thenExactCleanup(
            address(0xabc1),
            SafeCast.toUint48(vm.getBlockTimestamp())
        );
        _restore(checkpoint);
        test_givenPendingAction_whenEmergencyCancels_thenExactCleanup(
            address(0xabc1),
            SafeCast.toUint48(vm.getBlockTimestamp() + 1 days - 1)
        );
        _restore(checkpoint);
        test_givenPendingAction_whenEmergencyCancels_thenExactCleanup(
            address(0xabc1),
            SafeCast.toUint48(vm.getBlockTimestamp() + 4 days)
        );
        _restore(checkpoint);
        test_givenPendingAction_whenEmergencyCancels_thenExactCleanup(
            address(0xabc1),
            SafeCast.toUint48(vm.getBlockTimestamp() + 4 days + 1)
        );
        _restore(checkpoint);
        test_givenPendingAction_whenEmergencyCancels_thenExactCleanup(
            address(0xabc1),
            type(uint48).max
        );
    }

    // Scenarios: BLINCT-CANCEL-I01.
    function test_whenUnknownIdAtTypeBounds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenActionUnknown_revertsBeforeAuthorization(0, address(0));
        _restore(checkpoint);
        test_whenActionUnknown_revertsBeforeAuthorization(type(uint64).max, address(0));
    }

    // Scenarios: BLINCT-CANCEL-A02.
    function test_givenOtherAdministrativeRoles_whenCancelled_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenCallerLacksEmergency_reverts(address(this));
        _restore(checkpoint);
        test_whenCallerLacksEmergency_reverts(_recipient);
    }

    function _cancelWithoutReadiness() internal {
        _rolesAdmin.grantRole(EMERGENCY_ROLE, _recipient);
        _rejectInventoryReadinessReads();
        bytes32 funds = _inventoryDigest();
        vm.prank(_recipient);
        _timelock.cancelQueuedAction(_pendingId);
        _assertCleared(_pendingId);
        assertTrue(
            _timelock.getQueuedAction(_pendingId).cancelled,
            "Target cannot strand cancellation"
        );
        assertEq(_inventoryDigest(), funds, "Cancellation leaves Inventory intact");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth, unused-return)
