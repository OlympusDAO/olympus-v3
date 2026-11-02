// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts, delays and timestamps are independent expected test values.
// Tests intentionally read state after calls to assert effects and rollback.
// Expected-revert calls and repeated configuration probes discard their return values.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth, unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";
import {RecoveryCallbackOhm} from "./fixtures/RecoveryCallbackOhm.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {Actions, toKeycode} from "src/Kernel.sol";
import {BurnerLoansConfig} from "src/policies/burnerloans/BurnerLoansConfig.sol";
import {BurnerLoansInventory} from "src/policies/burnerloans/BurnerLoansInventory.sol";

contract BurnerLoansInventoryConfigTimelockExecuteQueuedActionTest is
    BurnerLoansInventoryConfigTimelockTest
{
    // Scenarios: BLINCT-EXECUTE-D01.
    function test_givenControllerChanged_whenActionExecutes_reverts(
        address caller_
    ) public givenPendingRecovery {
        _inventory.setConfigOperator(_inventoryConfigurator);
        _makeReady(_pendingId);
        _expectExecuteRejected(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                _pendingId,
                uint256(0),
                _key(),
                keccak256(abi.encode(address(_timelock))),
                keccak256(abi.encode(_inventoryConfigurator))
            ),
            caller_
        );
    }

    // Scenarios: BLINCT-EXECUTE-D02.
    function test_givenCoreSettlementBusy_whenRecoveryExecutes_revertsAndCanRetry(
        address caller_
    ) public givenProviderSurplus givenPendingRecovery {
        _makeReady(_pendingId);
        bytes memory reason = abi.encodeWithSelector(
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector
        );
        vm.mockCallRevert(address(_core), abi.encodeCall(_core.requireNotReentrant, ()), reason);
        _expectExecuteRejected(reason, caller_);
        vm.clearMockedCalls();
        vm.prank(caller_);
        _timelock.executeQueuedAction(_pendingId);
        _assertBacking(50e9);
        _assertCleared(_pendingId);
        assertEq(
            _ohm.balanceOf(_treasury()),
            1e9,
            "Recovery pays original surplus exactly once after guard restoration"
        );
    }

    // Scenarios: BLINCT-EXECUTE-L01.
    function test_givenInventoryDisabledAfterQueue_whenBurnExecutes_reverts()
        public
        givenProviderSurplus
    {
        _pendingId = _timelock.queueBurnSurplus();
        _inventory.disable("");
        _makeReady(_pendingId);
        _expectExecuteRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_inventory)
            ),
            address(this)
        );
    }

    // Scenarios: BLINCT-EXECUTE-L02, BLINCT-EXECUTE-N02, BLINCT-EXECUTE-N03, BLINCT-EXECUTE-P01.
    function test_givenReadyRecovery_whenAnyoneExecutes_thenExactCleanup(
        uint48 now_,
        address caller_,
        bool inventoryEnabled_
    ) public givenProviderSurplus givenPendingRecovery {
        ITimelockBatchQueue.QueuedAction memory beforeAction = _timelock.getQueuedAction(
            _pendingId
        );
        now_ = SafeCast.toUint48(bound(now_, beforeAction.executableAt, beforeAction.expiresAt));
        vm.warp(now_);
        _setState(_inventory, true, inventoryEnabled_);
        uint256 beforeTreasury = _ohm.balanceOf(_treasury());
        uint256 beforeSupply = _ohm.totalSupply();
        vm.expectEmit(address(_inventory));
        emit IBurnerLoansInventory.SurplusRescued(1e9);
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockSubActionExecuted(
            _pendingId,
            address(_inventory),
            IBurnerLoansInventory.rescueSurplus.selector,
            0
        );
        vm.expectEmit(address(_timelock));
        emit ITimelockBatchQueue.TimelockActionExecuted(_pendingId, caller_);
        vm.prank(caller_);
        _timelock.executeQueuedAction(_pendingId);
        _assertBacking(50e9);
        _assertCleared(_pendingId);
        ITimelockBatchQueue.QueuedAction memory afterAction = _timelock.getQueuedAction(_pendingId);
        assertTrue(afterAction.executed, "Execution recorded");
        assertFalse(afterAction.cancelled, "No cancellation");
        assertEq(afterAction.proposer, beforeAction.proposer, "Proposer retained");
        assertEq(afterAction.queuedAt, beforeAction.queuedAt, "Queue time retained");
        assertEq(afterAction.executableAt, beforeAction.executableAt, "Notice retained");
        assertEq(afterAction.expiresAt, beforeAction.expiresAt, "Expiry retained");
        assertEq(_inventory.isEnabled(), inventoryEnabled_, "Recovery leaves target pause intact");
        assertEq(
            _ohm.balanceOf(_treasury()),
            beforeTreasury + 1e9,
            "Only surplus delivered to live Treasury"
        );
        assertEq(_ohm.totalSupply(), beforeSupply, "Rescue preserves OHM supply");
    }

    // Scenarios: BLINCT-EXECUTE-N01.
    function test_givenNoticeNotElapsed_whenExecuted_reverts(
        uint48 now_,
        address caller_
    ) public givenPendingRecovery {
        ITimelockBatchQueue.QueuedAction memory action = _timelock.getQueuedAction(_pendingId);
        now_ = SafeCast.toUint48(bound(now_, action.queuedAt, uint256(action.executableAt) - 1));
        vm.warp(now_);
        _expectExecuteRejected(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                _pendingId,
                action.executableAt
            ),
            caller_
        );
    }

    // Scenarios: BLINCT-EXECUTE-N04.
    function test_givenExpiredWindow_whenExecuted_reverts(
        uint256 now_,
        address caller_
    ) public givenPendingRecovery {
        uint48 expiry = _timelock.getQueuedAction(_pendingId).expiresAt;
        now_ = bound(now_, uint256(expiry) + 1, type(uint256).max);
        vm.warp(now_);
        _expectExecuteRejected(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                _pendingId,
                expiry
            ),
            caller_
        );
    }

    // Scenarios: BLINCT-EXECUTE-L03.
    function test_givenActiveDisabledTimelock_whenExecuted_reverts(
        address caller_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _setState(_timelock, true, false);
        _expectExecuteRejected(abi.encodeWithSelector(IEnabler.NotEnabled.selector), caller_);
    }

    // Scenarios: BLINCT-EXECUTE-L05.
    function test_givenInactiveDisabledTimelock_whenExecuted_reverts(
        address caller_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _setState(_timelock, false, false);
        _expectExecuteRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            ),
            caller_
        );
    }

    // Scenarios: BLINCT-EXECUTE-L04.
    function test_givenInactiveTimelock_whenExecuted_reverts(
        address caller_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _setState(_timelock, false, true);
        _expectExecuteRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            ),
            caller_
        );
    }

    // Scenarios: BLINCT-EXECUTE-L06, BLINCT-EXECUTE-L07.
    function test_givenInactiveInventory_whenExecuted_reverts(
        bool enabled_,
        address caller_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _setState(_inventory, false, enabled_);
        _expectExecuteRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_inventory)
            ),
            caller_
        );
    }

    // Scenarios: BLINCT-EXECUTE-D03.
    function test_givenInventoryKernelDrift_whenExecuted_reverts(
        address caller_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _mockInventoryKernel(address(0xbeef));
        _expectExecuteRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_inventory),
                address(_kernel),
                address(0xbeef)
            ),
            caller_
        );
    }

    // Scenarios: BLINCT-EXECUTE-D04.
    function test_givenControllerCleared_whenExecuted_reverts(
        address caller_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _inventory.setConfigOperator(address(0));
        _expectExecuteRejected(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                _pendingId,
                uint256(0),
                _key(),
                keccak256(abi.encode(address(_timelock))),
                keccak256(abi.encode(address(0)))
            ),
            caller_
        );
    }

    // Scenarios: BLINCT-EXECUTE-P04.
    function test_givenControllerRotatesBack_whenExecuted_thenOriginalCommitmentMatches(
        address caller_
    ) public givenProviderSurplus givenPendingRecovery {
        _inventory.setConfigOperator(_inventoryConfigurator);
        _inventory.setConfigOperator(address(_timelock));
        _makeReady(_pendingId);
        vm.prank(caller_);
        _timelock.executeQueuedAction(_pendingId);
        _assertBacking(50e9);
        _assertCleared(_pendingId);
        assertEq(
            _ohm.balanceOf(_treasury()),
            1e9,
            "Original recovery executes once after controller restoration"
        );
    }

    // Scenarios: BLINCT-EXECUTE-P05.
    function test_givenExecutedAction_whenRequeued_thenFreshIdOwnsKey()
        public
        givenPendingRecovery
    {
        _makeReady(_pendingId);
        _timelock.executeQueuedAction(_pendingId);
        uint64 id = _timelock.queueBurnSurplus();
        assertEq(id, uint256(_pendingId) + 1, "New queue gets next ID");
        _assertQueued(id, IBurnerLoansInventory.burnSurplus.selector, address(this));
        assertTrue(_timelock.getQueuedAction(_pendingId).executed, "Execution tombstone retained");
    }

    function _expectExecuteRejected(bytes memory reason_, address caller_) internal {
        bytes32 state = _queueDigest(_pendingId);
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _timelock.executeQueuedAction(_pendingId);
        assertEq(
            _queueDigest(_pendingId),
            state,
            "Failed execution restores payload, state guards, shared key, balances, claims and approval"
        );
    }

    // Scenarios: BLINCT-EXECUTE-I01.
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
        _timelock.executeQueuedAction(id_);
        vm.expectRevert(reason);
        vm.prank(caller_);
        _timelock.getQueuedAction(id_);
        _assertTerminalGetters(id_, reason, caller_);
        assertEq(_queueDigest(_pendingId), state, "Unknown ID has no side effects");
    }

    // Scenarios: BLINCT-EXECUTE-I02.
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
        _timelock.executeQueuedAction(_pendingId);
        _assertTerminalGetters(_pendingId, reason, caller_);
        _assertCleared(_pendingId);
        assertEq(_inventoryDigest(), funds, "Terminal replay performs no second dispatch");
    }

    // Scenarios: BLINCT-EXECUTE-I03.
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
        _timelock.executeQueuedAction(_pendingId);
        _assertTerminalGetters(_pendingId, reason, caller_);
        _assertCleared(_pendingId);
        assertEq(_inventoryDigest(), funds, "Terminal replay performs no second dispatch");
    }

    error TargetOperationFailed();

    // Scenarios: BLINCT-EXECUTE-T01.
    function test_givenRescueTransferFailure_whenExecuted_thenRollbackAndRetry(
        address caller_
    ) public givenProviderSurplus givenPendingRecovery {
        _makeReady(_pendingId);
        vm.mockCallRevert(
            address(_ohm),
            abi.encodeCall(_ohm.transfer, (_treasury(), uint256(1e9))),
            abi.encodeWithSelector(TargetOperationFailed.selector)
        );
        _expectExecuteRejected(abi.encodeWithSelector(TargetOperationFailed.selector), caller_);
        vm.clearMockedCalls();
        vm.prank(caller_);
        _timelock.executeQueuedAction(_pendingId);
        _assertBacking(50e9);
        _assertCleared(_pendingId);
        assertEq(_ohm.balanceOf(_treasury()), 1e9, "Retry pays original live surplus once");
    }

    // Scenarios: BLINCT-EXECUTE-T04.
    function test_givenMintrBurnFailure_whenExecuted_thenRollbackAndRetry(
        address caller_
    ) public givenProviderSurplus {
        _pendingId = _timelock.queueBurnSurplus();
        _makeReady(_pendingId);
        address mintr = address(_kernel.getModuleForKeycode(toKeycode("MINTR")));
        vm.mockCallRevert(
            mintr,
            abi.encodeWithSignature("burnOhm(address,uint256)", address(_inventory), uint256(1e9)),
            abi.encodeWithSelector(TargetOperationFailed.selector)
        );
        _expectExecuteRejected(abi.encodeWithSelector(TargetOperationFailed.selector), caller_);
        vm.clearMockedCalls();
        uint256 supply = _ohm.totalSupply();
        vm.prank(caller_);
        _timelock.executeQueuedAction(_pendingId);
        _assertBacking(50e9);
        _assertCleared(_pendingId);
        assertEq(_ohm.totalSupply(), supply - 1e9, "Retry burns surplus exactly once");
    }

    // Scenarios: BLINCT-EXECUTE-T02.
    function test_givenTargetEmptyFailure_whenExecuted_thenWrappedError(
        address caller_
    ) public givenPendingRecovery {
        _expectWrappedTargetFailure(bytes(""), caller_);
    }

    // Scenarios: BLINCT-EXECUTE-T03.
    function test_givenTargetCappedFailure_whenExecuted_thenWrappedError(
        address caller_
    ) public givenPendingRecovery {
        _expectWrappedTargetFailure(new bytes(256), caller_);
    }

    // Scenarios: BLINCT-EXECUTE-T03.
    function test_givenTargetReturnBomb_whenExecuted_thenCappedWrapper()
        public
        givenPendingRecovery
    {
        _expectWrappedTargetFailure(new bytes(4096), address(this));
    }

    function _expectWrappedTargetFailure(bytes memory data_, address caller_) internal {
        _makeReady(_pendingId);
        vm.mockCallRevert(address(_inventory), abi.encodeCall(_inventory.rescueSurplus, ()), data_);
        _expectExecuteRejected(
            abi.encodeWithSelector(
                IBurnerLoansInventoryConfigTimelock
                    .BurnerLoansInventoryTimelock_SubActionCallFailed
                    .selector,
                IBurnerLoansInventory.rescueSurplus.selector
            ),
            caller_
        );
    }

    function test_givenTargetFailureBelowCap_whenExecuted_thenExactBytes(
        bytes memory data_
    ) public givenPendingRecovery {
        vm.assume(data_.length > 0 && data_.length < 256);
        _makeReady(_pendingId);
        vm.mockCallRevert(address(_inventory), abi.encodeCall(_inventory.rescueSurplus, ()), data_);
        _expectExecuteRejected(data_, address(this));
    }

    // Scenarios: BLINCT-EXECUTE-P02.
    function test_givenConfigReplaced_whenExecuted_thenImmutableInventoryUsed(
        address caller_
    ) public givenProviderSurplus givenPendingRecovery {
        BurnerLoansConfig replacement = new BurnerLoansConfig(_kernel, _core);
        _risk.setConfigOperator(address(replacement));
        _core.setConfigOperator(address(replacement));
        assertEq(
            address(_timelock.inventory()),
            address(_inventory),
            "Core Config rotation does not redirect recovery"
        );
        _makeReady(_pendingId);
        vm.prank(caller_);
        _timelock.executeQueuedAction(_pendingId);
        _assertBacking(50e9);
        _assertCleared(_pendingId);
        assertEq(
            _ohm.balanceOf(_treasury()),
            1e9,
            "Same Inventory recovered after Config rotation"
        );
    }

    // Scenarios: BLINCT-EXECUTE-P03.
    function test_givenCoreInventoryReplaced_whenExecuted_thenOriginalTargetRecovered(
        address caller_
    ) public givenPendingRecovery {
        // Both ledgers are empty, so Core replacement is reachable without migrating claims.
        BurnerLoansInventory replacement = new BurnerLoansInventory(
            _kernel,
            IERC20(address(_ohm)),
            address(_core)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.enable("");
        _core.setInventory(address(replacement));
        _ohm.mint(address(_inventory), 1e9);
        _makeReady(_pendingId);
        vm.expectCall(address(_inventory), abi.encodeCall(_inventory.rescueSurplus, ()), 1);
        vm.prank(caller_);
        _timelock.executeQueuedAction(_pendingId);
        assertEq(
            address(_timelock.inventory()),
            address(_inventory),
            "Immutable retired target retained"
        );
        assertEq(_ohm.balanceOf(address(replacement)), 0, "Replacement receives no recovery funds");
        assertEq(_ohm.balanceOf(_treasury()), 1e9, "Original Inventory pays Treasury");
        _assertCleared(_pendingId);
    }

    // Scenarios: BLINCT-EXECUTE-C01.
    function test_givenRescueTokenCallback_whenNestedRescuePropagates_thenCompleteRollback()
        public
        givenProviderSurplus
        givenPendingRecovery
    {
        // Preserve the existing OZ token balances while adding a transfer callback.
        RecoveryCallbackOhm template = new RecoveryCallbackOhm();
        vm.etch(address(_ohm), address(template).code);
        RecoveryCallbackOhm token = RecoveryCallbackOhm(address(_ohm));
        _rolesAdmin.grantRole(ADMIN_ROLE, address(token));
        token.arm(address(_inventory), abi.encodeCall(_inventory.rescueSurplus, ()));
        assertEq(
            _ohm.balanceOf(address(_inventory)),
            51e9,
            "Callback installation preserves provider backing and surplus"
        );
        _makeReady(_pendingId);
        _expectExecuteRejected(
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector),
            address(this)
        );
        token.arm(address(0), bytes(""));
        _timelock.executeQueuedAction(_pendingId);
        _assertBacking(50e9);
        _assertCleared(_pendingId);
        assertEq(_ohm.balanceOf(_treasury()), 1e9, "Callback cannot double-pay recovery");
    }

    // Scenarios: BLINCT-EXECUTE-L02, BLINCT-EXECUTE-N02, BLINCT-EXECUTE-N03, BLINCT-EXECUTE-P01.
    function test_givenExecutionEndpointSeeds_whenExecuted_thenExactCleanup() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenReadyRecovery_whenAnyoneExecutes_thenExactCleanup(
            SafeCast.toUint48(vm.getBlockTimestamp() + 1 days),
            address(0),
            true
        );
        _restore(checkpoint);
        test_givenReadyRecovery_whenAnyoneExecutes_thenExactCleanup(
            SafeCast.toUint48(vm.getBlockTimestamp() + 4 days),
            address(0),
            true
        );
        _restore(checkpoint);
        test_givenReadyRecovery_whenAnyoneExecutes_thenExactCleanup(
            SafeCast.toUint48(vm.getBlockTimestamp() + 1 days),
            address(0),
            false
        );
        _restore(checkpoint);
        test_givenReadyRecovery_whenAnyoneExecutes_thenExactCleanup(
            SafeCast.toUint48(vm.getBlockTimestamp() + 4 days),
            address(0),
            false
        );
    }

    // Scenarios: BLINCT-EXECUTE-N01.
    function test_givenNoticeEndpointSeeds_whenExecuted_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenNoticeNotElapsed_whenExecuted_reverts(
            SafeCast.toUint48(vm.getBlockTimestamp()),
            address(0)
        );
        _restore(checkpoint);
        test_givenNoticeNotElapsed_whenExecuted_reverts(
            SafeCast.toUint48(vm.getBlockTimestamp() + 1 days - 1),
            address(0)
        );
    }

    // Scenarios: BLINCT-EXECUTE-N04.
    function test_givenExpiredWindowEndpointSeeds_whenExecuted_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenExpiredWindow_whenExecuted_reverts(
            vm.getBlockTimestamp() + 4 days + 1,
            address(0)
        );
        _restore(checkpoint);
        test_givenExpiredWindow_whenExecuted_reverts(type(uint48).max, address(0));
        _restore(checkpoint);
        test_givenExpiredWindow_whenExecuted_reverts(type(uint256).max, address(0));
    }

    // Scenarios: BLINCT-EXECUTE-I01.
    function test_whenUnknownIdAtTypeBounds_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenActionUnknown_revertsBeforeAuthorization(0, address(0));
        _restore(checkpoint);
        test_whenActionUnknown_revertsBeforeAuthorization(type(uint64).max, address(0));
    }
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth, unused-return)
