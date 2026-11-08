// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";
import {PayoutRecoveryCallbackToken} from "./fixtures/PayoutRecoveryCallbackToken.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {BurnerLoansPayout} from "src/policies/burnerloans/BurnerLoansPayout.sol";

contract BurnerLoansPayoutConfigTimelockExecuteQueuedActionTest is
    BurnerLoansPayoutConfigTimelockTest
{
    error DispatchFailed();

    // Scenarios: BLCUCT-EXECUTE-P01.
    function test_givenQueuedReferralRescue_whenExecuted(
        address executor_,
        bool payoutPaused_
    ) public {
        _fundPendingReferral(40);
        uint64 id = _payoutTimelock.queueRescuePendingPayout(
            address(_asset),
            _recipient,
            _borrower,
            40
        );
        ITimelockBatchQueue.QueuedAction memory q = _payoutTimelock.getQueuedAction(id);
        if (payoutPaused_) _payout.disable("");
        _makeReady(id);
        uint256 beforeBalance = _asset.balanceOf(_borrower);
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.PendingReferralFeeRescued(
            address(_asset),
            _recipient,
            _borrower,
            40
        );
        vm.prank(executor_);
        _payoutTimelock.executeQueuedAction(id);
        assertEq(
            _asset.balanceOf(_borrower),
            beforeBalance + 40,
            "Timelock redirects exactly the approved referral fee"
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), _recipient),
            0,
            "Referral bucket cleared"
        );
        assertEq(
            _payout.getPendingReferralRecipients(address(_asset)).length,
            0,
            "Referral index cleared"
        );
        (, uint256 referral, , , uint256 total) = _payout.pendingAmounts(address(_asset));
        assertEq(referral, 0, "Aggregate referral reserve cleared");
        assertEq(total, 0, "Aggregate payout reserve cleared");
        _assertCleared(id, q.actions);
        assertTrue(_payoutTimelock.getQueuedAction(id).executed, "Action marked executed");
    }

    // Scenarios: BLCUCT-EXECUTE-D08.
    function test_givenReferralPaidDuringNotice_whenQueuedRescueExecuted_reverts(
        address executor_
    ) public {
        _fundPendingReferral(40);
        uint64 id = _payoutTimelock.queueRescuePendingPayout(
            address(_asset),
            _recipient,
            _borrower,
            40
        );
        assertEq(
            _payout.transferPendingPayout(address(_asset), _recipient),
            40,
            "Normal retry pays the original referrer during notice"
        );
        _makeReady(id);
        _expectExecutionRejected(
            id,
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
                address(_asset),
                uint256(40),
                uint256(0)
            ),
            executor_
        );
        assertEq(
            _payout.pendingReferralFee(address(_asset), _recipient),
            0,
            "Failed rescue recreates no paid liability"
        );
        _fundPendingReferral(40);
        uint256 beforeBalance = _asset.balanceOf(_borrower);
        vm.prank(executor_);
        _payoutTimelock.executeQueuedAction(id);
        assertEq(
            _asset.balanceOf(_borrower),
            beforeBalance + 40,
            "Restored live entitlement allows the same queued action to complete"
        );
        assertTrue(
            _payoutTimelock.getQueuedAction(id).executed,
            "Retained action executes after restoration within its original window"
        );
    }

    // Scenarios: BLCUCT-EXECUTE-L01, BLCUCT-EXECUTE-N02.
    function test_givenReadyAction_whenExecuted_thenExactDispatchAndCleanup(
        address executor_,
        address reader_,
        uint48 now_
    ) public givenPendingRecovery {
        _asset.mint(address(_payout), 7);
        ITimelockBatchQueue.QueuedAction memory q = _payoutTimelock.getQueuedAction(_pendingId);
        now_ = uint48(bound(now_, q.executableAt, q.expiresAt));
        vm.warp(now_);
        uint64 other = _payoutTimelock.queueSetSendYieldToDistributor(false);
        bytes32 retained = _queueDigest(other);
        uint256 beforeBalance = _asset.balanceOf(_borrower);
        vm.expectCall(
            address(_payout),
            abi.encodeCall(_payout.rescue, (address(_asset), _borrower)),
            uint64(1)
        );
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.AssetRescued(address(_asset), _borrower, 7);
        vm.expectEmit(address(_payoutTimelock));
        emit ITimelockBatchQueue.TimelockSubActionExecuted(
            _pendingId,
            address(_payout),
            IBurnerLoansPayout.rescue.selector,
            0
        );
        vm.expectEmit(address(_payoutTimelock));
        emit ITimelockBatchQueue.TimelockActionExecuted(_pendingId, executor_);
        vm.prank(executor_);
        _payoutTimelock.executeQueuedAction(_pendingId);
        assertEq(
            _asset.balanceOf(_borrower),
            beforeBalance + 7,
            "Original target pays exact surplus"
        );
        vm.prank(reader_);
        ITimelockBatchQueue.QueuedAction memory afterAction = _payoutTimelock.getQueuedAction(
            _pendingId
        );
        assertTrue(afterAction.executed, "Executed");
        assertFalse(afterAction.cancelled, "Not cancelled");
        assertEq(afterAction.proposer, q.proposer, "Retained proposer");
        assertEq(afterAction.queuedAt, q.queuedAt, "Retained queue time");
        assertEq(afterAction.executableAt, q.executableAt, "Retained readiness");
        assertEq(afterAction.expiresAt, q.expiresAt, "Retained expiry");
        _assertCleared(_pendingId, q.actions);
        assertEq(_queueDigest(other), retained, "Unrelated work retained");
        _removedGetters(
            _pendingId,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                _pendingId
            ),
            reader_,
            0,
            0
        );
    }

    // Scenarios: BLCUCT-EXECUTE-N01.
    function test_givenBeforeNotice_whenExecuted_reverts(
        address executor_,
        uint48 now_
    ) public givenPendingRecovery {
        uint48 ready = _payoutTimelock.getQueuedAction(_pendingId).executableAt;
        vm.warp(bound(now_, 0, ready - 1));
        _expectExecutionRejected(
            _pendingId,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                _pendingId,
                ready
            ),
            executor_
        );
    }

    // Scenarios: BLCUCT-EXECUTE-N03.
    function test_givenAfterExpiry_whenExecuted_reverts(
        address executor_,
        uint48 now_
    ) public givenPendingRecovery {
        uint48 expiry = _payoutTimelock.getQueuedAction(_pendingId).expiresAt;
        vm.warp(bound(now_, uint256(expiry) + 1, type(uint48).max));
        _expectExecutionRejected(
            _pendingId,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                _pendingId,
                expiry
            ),
            executor_
        );
    }

    // Scenarios: BLCUCT-EXECUTE-I01.
    function test_whenUnknownActionReadOrExecuted_reverts(
        address caller_,
        uint64 id_,
        uint256 sub_,
        uint256 state_
    ) public {
        _setState(_payoutTimelock, false, false);
        bytes memory reason = abi.encodeWithSelector(
            ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
            id_
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _payoutTimelock.executeQueuedAction(id_);
        vm.expectRevert(reason);
        vm.prank(caller_);
        _payoutTimelock.getQueuedAction(id_);
        _removedGetters(id_, reason, caller_, sub_, state_);
    }

    // Scenarios: BLCUCT-EXECUTE-I02.
    function test_givenExecuted_whenExecutedAgain_reverts(
        address caller_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _payoutTimelock.executeQueuedAction(_pendingId);
        _expectExecutionRejected(
            _pendingId,
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                _pendingId
            ),
            caller_
        );
    }

    // Scenarios: BLCUCT-EXECUTE-I03.
    function test_givenCancelled_whenExecuted_reverts(
        address caller_,
        uint256 sub_,
        uint256 state_
    ) public givenPendingRecovery {
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(this));
        _payoutTimelock.cancelQueuedAction(_pendingId);
        bytes memory reason = abi.encodeWithSelector(
            ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
            _pendingId
        );
        _expectExecutionRejected(_pendingId, reason, caller_);
        _removedGetters(_pendingId, reason, caller_, sub_, state_);
    }

    // Scenarios: BLCUCT-EXECUTE-L02.
    function test_givenActiveDisabled_whenExecuted_reverts(
        address executor_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _setState(_payoutTimelock, true, false);
        _expectExecutionRejected(
            _pendingId,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            executor_
        );
    }

    // Scenarios: BLCUCT-EXECUTE-L04.
    function test_givenInactiveDisabled_whenExecuted_reverts(
        address executor_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _setState(_payoutTimelock, false, false);
        _expectExecutionRejected(
            _pendingId,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            executor_
        );
    }

    // Scenarios: BLCUCT-EXECUTE-L03.
    function test_givenInactiveEnabled_whenExecuted_reverts(
        address executor_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _setState(_payoutTimelock, false, true);
        _expectExecutionRejected(
            _pendingId,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payoutTimelock)
            ),
            executor_
        );
    }

    // Scenarios: BLCUCT-EXECUTE-D01.
    function test_givenTargetKernelChanged_whenExecuted_reverts(
        address executor_
    ) public givenPendingRecovery {
        _makeReady(_pendingId);
        _mockPayoutKernel(address(0x1234));
        _expectExecutionRejected(
            _pendingId,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_payout),
                address(_kernel),
                address(0x1234)
            ),
            executor_
        );
    }

    // Scenarios: BLCUCT-EXECUTE-D02.
    function test_givenControllerReplaced_whenQueuedActionExecutes_reverts(
        address executor_
    ) public givenPendingRecovery {
        bytes32 key = _scopedKey(_rescueAction());
        _payout.setConfigOperator(_recipient);
        _makeReady(_pendingId);
        _expectExecutionRejected(
            _pendingId,
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                _pendingId,
                uint256(0),
                key,
                keccak256(abi.encode(address(_payoutTimelock))),
                keccak256(abi.encode(_recipient))
            ),
            executor_
        );
    }

    // Scenarios: BLCUCT-EXECUTE-D04.
    function test_givenDeselectedActivePayout_whenQueuedRescueExecutes_thenOriginalInstancePays(
        address executor_,
        bool coreActive_,
        bool coreEnabled_,
        bool payoutEnabled_
    ) public {
        _asset.mint(address(_payout), 123);
        uint64 id = _payoutTimelock.queueRescue(address(_asset), _borrower);
        BurnerLoansPayout replacement = new BurnerLoansPayout(_kernel, address(_core));
        _kernel.executeAction(Actions.ActivatePolicy, address(replacement));
        replacement.enable("");
        _core.setPayout(address(replacement));
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, true, payoutEnabled_);
        _makeReady(id);
        uint256 beforeBalance = _asset.balanceOf(_borrower);
        vm.prank(executor_);
        _payoutTimelock.executeQueuedAction(id);
        assertEq(_asset.balanceOf(_borrower), beforeBalance + 123, "Retired target pays");
        assertEq(_asset.balanceOf(address(replacement)), 0, "No retargeting");
        assertEq(_payout.configOperator(), address(_payoutTimelock), "Old controller retained");
        _assertCleared(id, _single(_rescueAction()));
    }

    // Scenarios: BLCUCT-EXECUTE-D05.
    function test_givenFeeDistributorReplaced_whenExecuted_reverts(
        address executor_,
        bool requested_
    ) public {
        RevenueDistributor first = _distributor();
        uint64 id = _payoutTimelock.queueSetSendFeesToDistributor(requested_);
        bytes32 queue = _queueDigest(id);
        RevenueDistributor second = _distributor();
        assertEq(_queueDigest(id), queue, "Replacement preserves proposal");
        bytes32 key = _scopedKey(
            _action(IBurnerLoansPayout.setSendFeesToDistributor.selector, abi.encode(requested_))
        );
        _makeReady(id);
        _expectExecutionRejected(
            id,
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                id,
                uint256(0),
                key,
                keccak256(abi.encode(address(_payoutTimelock), false, address(first))),
                keccak256(abi.encode(address(_payoutTimelock), false, address(second)))
            ),
            executor_
        );
    }

    // Scenarios: BLCUCT-EXECUTE-D06.
    function test_givenYieldDistributorReplaced_whenExecuted_reverts(
        address executor_,
        bool requested_
    ) public {
        RevenueDistributor first = _distributor();
        uint64 id = _payoutTimelock.queueSetSendYieldToDistributor(requested_);
        bytes32 queue = _queueDigest(id);
        RevenueDistributor second = _distributor();
        assertEq(_queueDigest(id), queue, "Replacement preserves proposal");
        bytes32 key = _scopedKey(
            _action(IBurnerLoansPayout.setSendYieldToDistributor.selector, abi.encode(requested_))
        );
        _makeReady(id);
        _expectExecutionRejected(
            id,
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                id,
                uint256(0),
                key,
                keccak256(abi.encode(address(_payoutTimelock), false, address(first))),
                keccak256(abi.encode(address(_payoutTimelock), false, address(second)))
            ),
            executor_
        );
    }

    // Scenarios: BLCUCT-EXECUTE-D03.
    function test_givenEachPendingRescueCommitmentChanged_whenExecuted_reverts(
        address executor_
    ) public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 field; field < 3; ++field) {
            _fundPending(20);
            _distributor();
            uint64 id = _payoutTimelock.queueRescuePendingPayout(
                address(_asset),
                _recipient,
                _borrower,
                5
            );
            ITimelockBatchQueue.BatchAction memory action = _action(
                IBurnerLoansPayout.rescuePendingPayout.selector,
                abi.encode(address(_asset), _recipient, _borrower, uint256(5))
            );
            bytes32 expected = _stateHash(action);
            if (field == 0) _payout.setSendFeesToDistributor(true);
            if (field == 1) _distributor();
            if (field == 2)
                _kernel.executeAction(Actions.UpgradeModule, address(new OlympusTreasury(_kernel)));
            bytes32 current = keccak256(
                abi.encode(
                    address(_payoutTimelock),
                    _payout.sendFeesToDistributor(),
                    _payout.revenueDistributor(),
                    _payout.treasury()
                )
            );
            _makeReady(id);
            _expectExecutionRejected(
                id,
                abi.encodeWithSelector(
                    IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                    id,
                    uint256(0),
                    _scopedKey(action),
                    expected,
                    current
                ),
                executor_
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCUCT-EXECUTE-D03.
    function test_givenFeeOrYieldFlagChanged_whenExecuted_reverts(
        address executor_,
        bool yield_
    ) public {
        _distributor();
        bytes4 selector = yield_
            ? IBurnerLoansPayout.setSendYieldToDistributor.selector
            : IBurnerLoansPayout.setSendFeesToDistributor.selector;
        uint64 id = yield_
            ? _payoutTimelock.queueSetSendYieldToDistributor(true)
            : _payoutTimelock.queueSetSendFeesToDistributor(true);
        bytes32 expected = keccak256(
            abi.encode(address(_payoutTimelock), false, _payout.revenueDistributor())
        );
        if (yield_) _payout.setSendYieldToDistributor(true);
        else _payout.setSendFeesToDistributor(true);
        bytes32 current = keccak256(
            abi.encode(address(_payoutTimelock), true, _payout.revenueDistributor())
        );
        _makeReady(id);
        _expectExecutionRejected(
            id,
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector,
                id,
                uint256(0),
                _scopedKey(_action(selector, abi.encode(true))),
                expected,
                current
            ),
            executor_
        );
    }

    // Scenarios: BLCUCT-EXECUTE-T01.
    function test_givenLateDispatchFailure_whenExecuted_thenAtomicRollbackAndRetry(
        address executor_
    ) public {
        _distributor();
        _asset.mint(address(_payout), 7);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _action(
            IBurnerLoansPayout.setSendFeesToDistributor.selector,
            abi.encode(true)
        );
        actions[1] = _rescueAction();
        uint64 id = _payoutTimelock.queueBatch(actions);
        _makeReady(id);
        vm.mockCallRevert(
            address(_payout),
            abi.encodeCall(_payout.rescue, (address(_asset), _borrower)),
            abi.encodeWithSelector(DispatchFailed.selector)
        );
        _expectExecutionRejected(id, abi.encodeWithSelector(DispatchFailed.selector), executor_);
        assertFalse(_payout.sendFeesToDistributor(), "Earlier setter rolls back");
        vm.clearMockedCalls();
        vm.prank(executor_);
        _payoutTimelock.executeQueuedAction(id);
        assertTrue(_payout.sendFeesToDistributor(), "Corrected retry applies setter");
        _assertCleared(id, actions);
    }

    // Scenarios: BLCUCT-EXECUTE-T02.
    function test_givenEmptyRevert_whenExecuted_reverts(
        address executor_
    ) public givenPendingRecovery {
        _mockDispatchFailure("");
        _expectExecutionRejected(_pendingId, _wrappedFailure(), executor_);
    }

    // Scenarios: BLCUCT-EXECUTE-T03.
    function test_givenShortRevert_whenExecuted_thenExactBytes(
        address executor_,
        uint8 length_,
        bytes32 word_
    ) public givenPendingRecovery {
        uint256 length = bound(length_, 1, 255);
        bytes memory reason = _errorBytes(length, word_);
        _mockDispatchFailure(reason);
        _expectExecutionRejected(_pendingId, reason, executor_);
    }

    // Scenarios: BLCUCT-EXECUTE-T04.
    function test_givenExactCapRevert_whenExecuted_thenWrapped(
        address executor_
    ) public givenPendingRecovery {
        _mockDispatchFailure(new bytes(256));
        _expectExecutionRejected(_pendingId, _wrappedFailure(), executor_);
    }

    // Scenarios: BLCUCT-EXECUTE-T05.
    function test_givenReturnDataBomb_whenExecuted_thenWrapped(
        address executor_,
        uint16 length_
    ) public givenPendingRecovery {
        _mockDispatchFailure(new bytes(bound(length_, 257, 65535)));
        _expectExecutionRejected(_pendingId, _wrappedFailure(), executor_);
    }

    function _mockDispatchFailure(bytes memory reason_) internal {
        _makeReady(_pendingId);
        vm.mockCallRevert(
            address(_payout),
            abi.encodeCall(_payout.rescue, (address(_asset), _borrower)),
            reason_
        );
    }

    function _wrappedFailure() internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IBurnerLoansPayoutConfigTimelock
                    .BurnerLoansPayoutTimelock_SubActionCallFailed
                    .selector,
                IBurnerLoansPayout.rescue.selector
            );
    }

    function _errorBytes(uint256 length_, bytes32 word_) internal pure returns (bytes memory data) {
        data = new bytes(length_);
        for (uint256 i; i < length_; ++i) data[i] = word_[i % 32];
    }

    // Scenarios: BLCUCT-EXECUTE-C01.
    function test_givenSameActionCallbackCaught_whenExecuted_thenOneDispatch(
        address executor_
    ) public {
        (PayoutRecoveryCallbackToken token, uint64 id, ) = _callbackFixture(false, false);
        vm.prank(executor_);
        _payoutTimelock.executeQueuedAction(id);
        assertEq(
            token.callbackRevertData(),
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            ),
            "Exact nested action state error"
        );
        assertEq(token.transferCallCount(), 1, "One payout");
        assertEq(token.balanceOf(_borrower), 7, "One outer payment");
        assertTrue(_payoutTimelock.getQueuedAction(id).executed, "Outer completes");

        _assertCleared(
            id,
            _single(
                _action(IBurnerLoansPayout.rescue.selector, abi.encode(address(token), _borrower))
            )
        );
    }

    // Scenarios: BLCUCT-EXECUTE-C02.
    function test_givenSameActionCallbackPropagates_whenExecuted_thenRollback(
        address executor_
    ) public {
        (PayoutRecoveryCallbackToken token, uint64 id, ) = _callbackFixture(false, true);
        bytes32 queue = _queueDigest(id);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                id
            )
        );
        vm.prank(executor_);
        _payoutTimelock.executeQueuedAction(id);
        assertEq(_queueDigest(id), queue, "Outer queue restored");
        assertEq(token.balanceOf(_borrower), 0, "No payout");
        assertEq(token.balanceOf(address(_payout)), 7, "Backing restored");
    }

    // Scenarios: BLCUCT-EXECUTE-C03.
    function test_givenOtherActionCallbackCaught_whenExecuted_thenNestedQueueRetained(
        address executor_
    ) public {
        (PayoutRecoveryCallbackToken token, uint64 id, uint64 nested) = _callbackFixture(
            true,
            false
        );
        bytes32 queue = _queueDigest(nested);
        vm.prank(executor_);
        _payoutTimelock.executeQueuedAction(id);
        assertEq(
            token.callbackRevertData(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "Nested Payout guard reached"
        );
        assertEq(_queueDigest(nested), queue, "Nested pending queue retained");
        assertEq(token.transferCallCount(), 1, "Exactly one payment");
        assertEq(token.balanceOf(_borrower), 7, "Outer pays once");

        _assertCleared(
            id,
            _single(
                _action(IBurnerLoansPayout.rescue.selector, abi.encode(address(token), _borrower))
            )
        );
    }

    // Scenarios: BLCUCT-EXECUTE-C04.
    function test_givenOtherActionCallbackPropagates_whenExecuted_thenBothQueuesRestored(
        address executor_
    ) public {
        (PayoutRecoveryCallbackToken token, uint64 id, uint64 nested) = _callbackFixture(
            true,
            true
        );
        bytes32 outer = _queueDigest(id);
        bytes32 inner = _queueDigest(nested);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(executor_);
        _payoutTimelock.executeQueuedAction(id);
        assertEq(_queueDigest(id), outer, "Outer queue restored");
        assertEq(_queueDigest(nested), inner, "Nested queue restored");
        assertEq(token.balanceOf(_borrower), 0, "No payment");
        assertEq(token.balanceOf(address(_payout)), 7, "Full backing restored");
    }

    function _callbackFixture(
        bool other_,
        bool bubble_
    ) internal returns (PayoutRecoveryCallbackToken token, uint64 id, uint64 nested) {
        token = new PayoutRecoveryCallbackToken();
        token.mint(address(_payout), 7);
        id = _payoutTimelock.queueRescue(address(token), _borrower);
        nested = other_ ? _payoutTimelock.queueSetSendFeesToDistributor(false) : id;
        _makeReady(id);
        token.setCallbackFrom(
            address(_payout),
            address(_payoutTimelock),
            abi.encodeCall(_payoutTimelock.executeQueuedAction, (nested))
        );
        token.setCallbackPhases(true, false);
        token.setBubbleCallbackFailure(bubble_);
    }

    // Scenarios: BLCTRP-P09, BLCTRP-P11, BLCTRP-P12, BLCTRP-P13.
    function test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount(
        address executor_,
        uint8 live_
    ) public {
        live_ = uint8(bound(live_, 5, 30));
        _fundPending(20);
        uint64 id = _payoutTimelock.queueRescuePendingPayout(
            address(_asset),
            _recipient,
            _borrower,
            5
        );
        uint64 other = _payoutTimelock.queueSetSendYieldToDistributor(false);
        bytes32 otherQueue = _queueDigest(other);
        if (live_ > 20) _fundPending(live_ - 20);
        if (live_ < 20)
            _payout.rescuePendingPayout(address(_asset), _recipient, _recipient, 20 - live_);
        _makeReady(id);
        uint256 beforeBalance = _asset.balanceOf(_borrower);
        vm.expectCall(
            address(_payout),
            abi.encodeCall(
                _payout.rescuePendingPayout,
                (address(_asset), _recipient, _borrower, uint256(5))
            ),
            uint64(1)
        );
        vm.prank(executor_);
        _payoutTimelock.executeQueuedAction(id);
        assertEq(_asset.balanceOf(_borrower), beforeBalance + 5, "Dispatch original exact amount");
        assertEq(
            _payout.pendingRecipientAmount(address(_asset), _recipient),
            uint256(live_) - 5,
            "Debit live entitlement"
        );
        _assertCleared(
            id,
            _single(
                _action(
                    IBurnerLoansPayout.rescuePendingPayout.selector,
                    abi.encode(address(_asset), _recipient, _borrower, uint256(5))
                )
            )
        );
        assertEq(_queueDigest(other), otherQueue, "Unrelated queue remains pending");
    }

    // Scenarios: BLCTRP-P10.
    function test_givenLiveEntitlementInsufficient_whenExecuted_thenTargetErrorAndRollback(
        address executor_
    ) public {
        _fundPending(20);
        uint64 id = _payoutTimelock.queueRescuePendingPayout(
            address(_asset),
            _recipient,
            _borrower,
            5
        );
        _payout.rescuePendingPayout(address(_asset), _recipient, _recipient, 16);
        _makeReady(id);
        _expectExecutionRejected(
            id,
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoans_InsufficientPendingPayout.selector,
                address(_asset),
                uint256(5),
                uint256(4)
            ),
            executor_
        );
    }

    function _expectExecutionRejected(
        uint64 id_,
        bytes memory reason_,
        address executor_
    ) internal {
        bytes32 queue = _queueDigest(id_);
        bytes32 funds = _payoutDigest();
        vm.prank(executor_);
        (bool ok, bytes memory data) = address(_payoutTimelock).call(
            abi.encodeCall(_payoutTimelock.executeQueuedAction, (id_))
        );
        assertFalse(ok, "Execution rejects");
        assertEq(data, reason_, "Exact execution failure");
        assertEq(_queueDigest(id_), queue, "Action, payload, guard and key ownership restored");
        assertEq(_payoutDigest(), funds, "Target state and funds restored");
    }

    // Scenarios: BLCUCT-EXECUTE-D05, BLCUCT-EXECUTE-D06, BLCUCT-EXECUTE-I01, BLCUCT-EXECUTE-N01, BLCUCT-EXECUTE-N03, BLCUCT-EXECUTE-T03, BLCUCT-EXECUTE-T05.
    function test_whenExecutionBoundarySeedsUsed() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenUnknownActionReadOrExecuted_reverts(address(0), 0, 0, 0);
        _restore(checkpoint);
        test_whenUnknownActionReadOrExecuted_reverts(_borrower, type(uint64).max, 1, 1);
        _restore(checkpoint);
        test_whenUnknownActionReadOrExecuted_reverts(
            address(this),
            0,
            type(uint256).max,
            type(uint256).max
        );
        _restore(checkpoint);
        test_givenBeforeNotice_whenExecuted_reverts(address(0), 1 days);
        _restore(checkpoint);
        test_givenAfterExpiry_whenExecuted_reverts(address(0), 4 days + 2);
        _restore(checkpoint);
        test_givenFeeDistributorReplaced_whenExecuted_reverts(_borrower, false);
        _restore(checkpoint);
        test_givenFeeDistributorReplaced_whenExecuted_reverts(_borrower, true);
        _restore(checkpoint);
        test_givenYieldDistributorReplaced_whenExecuted_reverts(_borrower, false);
        _restore(checkpoint);
        test_givenYieldDistributorReplaced_whenExecuted_reverts(_borrower, true);
        _restore(checkpoint);
        test_givenShortRevert_whenExecuted_thenExactBytes(_borrower, 1, bytes32(0));
        _restore(checkpoint);
        test_givenShortRevert_whenExecuted_thenExactBytes(
            _borrower,
            255,
            bytes32(type(uint256).max)
        );
        _restore(checkpoint);
        test_givenReturnDataBomb_whenExecuted_thenWrapped(_borrower, 257);
        _restore(checkpoint);
        test_givenReturnDataBomb_whenExecuted_thenWrapped(_borrower, type(uint16).max);
        _restore(checkpoint);
    }

    // Scenarios: BLCUCT-EXECUTE-L01, BLCUCT-EXECUTE-N02.
    function test_whenExactlyReady_thenExecuted() public {
        test_givenReadyAction_whenExecuted_thenExactDispatchAndCleanup(
            _borrower,
            address(0),
            1 days + 1
        );
    }

    // Scenarios: BLCUCT-EXECUTE-N02.
    function test_whenExactlyAtExpiry_thenExecuted() public {
        test_givenReadyAction_whenExecuted_thenExactDispatchAndCleanup(
            address(this),
            _recipient,
            4 days + 1
        );
    }

    // Scenarios: BLCTRP-P09, BLCTRP-P11.
    function test_givenEntitlementGrowsToThirty_whenExecuted_thenFiveDispatched() public {
        test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount(
            _borrower,
            30
        );
    }

    // Scenarios: BLCTRP-P09, BLCTRP-P12.
    function test_givenEntitlementFallsToEight_whenExecuted_thenFiveDispatched() public {
        test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount(_borrower, 8);
    }

    // Scenarios: BLCTRP-P09, BLCTRP-P13.
    function test_givenEntitlementEqualsFive_whenExecuted_thenFiveDispatched() public {
        test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount(_borrower, 5);
    }

    // Scenarios: BLCUCT-EXECUTE-D07.
    function test_givenInactivePayout_whenQueuedRescueExecutes_revertsThenRetries(
        address executor_
    ) public {
        _asset.mint(address(_payout), 123);
        uint64 id = _payoutTimelock.queueRescue(address(_asset), _borrower);
        _setState(_payout, false, true);
        _makeReady(id);
        _expectExecutionRejected(
            id,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            ),
            executor_
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        uint256 beforeBalance = _asset.balanceOf(_borrower);
        vm.prank(executor_);
        _payoutTimelock.executeQueuedAction(id);
        assertEq(
            _asset.balanceOf(_borrower),
            beforeBalance + 123,
            "Restored target discharges custody"
        );
        _assertCleared(id, _single(_rescueAction()));
    }
}
