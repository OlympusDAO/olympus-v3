// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

// =====================================================================================
// Mock
// =====================================================================================
contract MockTimelockBatchQueue is TimelockBatchQueue {
    error MockTimelockBatchQueue_SubActionRejected();
    error MockTimelockBatchQueue_SubActionRejectedAt(uint256 invocationIndex);
    error MockTimelockBatchQueue_BatchRejected();
    error MockTimelockBatchQueue_ExecutionRejected();
    error MockTimelockBatchQueue_CancellationRejected();

    struct ExecuteSubActionCall {
        uint64 actionId;
        uint256 index;
        address target;
        bytes4 selector;
        bytes32 payloadHash;
    }

    uint48 public constant MIN_DELAY = 1 days;
    uint48 public constant MAX_DELAY = 30 days;
    uint256 internal constant _NO_REJECT_INDEX = type(uint256).max;

    uint48 public executionWindow = 7 days;
    uint256 public maxBatchSizeOverride;
    uint256 public rejectSubActionAtIndex = _NO_REJECT_INDEX;

    address public queueCaller;
    address public executionCaller;
    address public cancellationCaller;

    bool public rejectSubAction;
    bool public rejectBatch;
    bool public rejectExecution;
    bool public rejectCancellation;

    address public callThroughTarget;
    uint256[] public executedValues;

    ExecuteSubActionCall[] internal _executeSubActionCalls;

    constructor(uint48 initialTimelockDelay_) TimelockBatchQueue(initialTimelockDelay_) {}

    // ---------- external wrappers ----------

    function queueAction(
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) external returns (uint64 actionId_) {
        return _queueAction(target_, selector_, payload_);
    }

    function queueBatchAction(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId_) {
        return _queueAction(actions_);
    }

    function setTimelockDelay(uint48 delay_) external {
        _setTimelockDelay(delay_);
    }

    // ---------- knob setters ----------

    function setExecutionWindow(uint48 v_) external {
        executionWindow = v_;
    }

    function setMaxBatchSizeOverride(uint256 v_) external {
        maxBatchSizeOverride = v_;
    }

    function setRejectSubActionAtIndex(uint256 v_) external {
        rejectSubActionAtIndex = v_;
    }

    function setQueueCaller(address v_) external {
        queueCaller = v_;
    }

    function setExecutionCaller(address v_) external {
        executionCaller = v_;
    }

    function setCancellationCaller(address v_) external {
        cancellationCaller = v_;
    }

    function setRejectSubAction(bool v_) external {
        rejectSubAction = v_;
    }

    function setRejectBatch(bool v_) external {
        rejectBatch = v_;
    }

    function setRejectExecution(bool v_) external {
        rejectExecution = v_;
    }

    function setRejectCancellation(bool v_) external {
        rejectCancellation = v_;
    }

    function setCallThroughTarget(address v_) external {
        callThroughTarget = v_;
    }

    // ---------- capture getters ----------

    function getExecuteSubActionCalls() external view returns (ExecuteSubActionCall[] memory) {
        return _executeSubActionCalls;
    }

    function getExecutedValues() external view returns (uint256[] memory) {
        return executedValues;
    }

    function getMaxBatchSize() external view returns (uint256) {
        return _maxBatchSize();
    }

    // ---------- hooks ----------

    function _validateSubAction(
        address caller_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        if (rejectSubAction) revert MockTimelockBatchQueue_SubActionRejected();
        if (queueCaller != address(0) && caller_ != queueCaller)
            revert MockTimelockBatchQueue_SubActionRejected();
        if (rejectSubActionAtIndex != _NO_REJECT_INDEX) {
            uint256 encodedIndex = abi.decode(action_.payload, (uint256));
            if (encodedIndex == rejectSubActionAtIndex)
                revert MockTimelockBatchQueue_SubActionRejectedAt(rejectSubActionAtIndex);
        }
    }

    function _validateBatch(
        address /* caller_ */,
        ITimelockBatchQueue.BatchAction[] memory /* actions_ */
    ) internal view override {
        if (rejectBatch) revert MockTimelockBatchQueue_BatchRejected();
    }

    function _validateExecution(
        address caller_,
        uint64 /* actionId_ */,
        ITimelockBatchQueue.QueuedAction memory /* action_ */
    ) internal view override {
        if (rejectExecution) revert MockTimelockBatchQueue_ExecutionRejected();
        if (executionCaller != address(0) && caller_ != executionCaller)
            revert MockTimelockBatchQueue_ExecutionRejected();
    }

    function _validateCancellation(
        address caller_,
        uint64 /* actionId_ */,
        ITimelockBatchQueue.QueuedAction memory /* action_ */
    ) internal view override {
        if (rejectCancellation) revert MockTimelockBatchQueue_CancellationRejected();
        if (cancellationCaller != address(0) && caller_ != cancellationCaller)
            revert MockTimelockBatchQueue_CancellationRejected();
    }

    function _executeSubAction(
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        _executeSubActionCalls.push(
            ExecuteSubActionCall({
                actionId: actionId_,
                index: index_,
                target: action_.target,
                selector: action_.selector,
                payloadHash: keccak256(action_.payload)
            })
        );

        if (callThroughTarget != address(0) && action_.target == callThroughTarget) {
            (bool ok, bytes memory ret) = action_.target.call(action_.payload);
            if (!ok) {
                assembly {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
            return;
        }

        executedValues.push(abi.decode(action_.payload, (uint256)));
    }

    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ < MIN_DELAY || delay_ > MAX_DELAY)
            revert ITimelockBatchQueue_TimelockDelayInvalid(delay_, MIN_DELAY, MAX_DELAY);
    }

    function _executionWindow() internal view override returns (uint48) {
        return executionWindow;
    }

    function _maxBatchSize() internal view override returns (uint256) {
        if (maxBatchSizeOverride != 0) return maxBatchSizeOverride;
        return super._maxBatchSize();
    }
}

// =====================================================================================
// Reentrant target: fallback re-enters queue with armed calldata
// =====================================================================================
contract ReentrantSubAction {
    address public immutable queue;
    bytes public reentryCalldata;
    bytes public lastReturnData;

    constructor(address queue_) {
        queue = queue_;
    }

    function arm(bytes calldata reentryCalldata_) external {
        reentryCalldata = reentryCalldata_;
    }

    fallback() external payable {
        (bool ok, bytes memory ret) = queue.call(reentryCalldata);
        lastReturnData = ret;
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    receive() external payable {}
}

// =====================================================================================
// Tests
// =====================================================================================
contract TimelockBatchQueueTest is Test {
    MockTimelockBatchQueue internal queue;
    ReentrantSubAction internal reentrant;

    address internal proposer = address(0x1111);
    address internal executor = address(0x2222);
    address internal canceller = address(0x3333);
    address internal target1 = address(0x4441);
    address internal target2 = address(0x4442);
    address internal target3 = address(0x4443);
    bytes4 internal selector1 = bytes4(keccak256("setValue(uint256)"));
    bytes4 internal selector2 = bytes4(keccak256("setOther(uint256)"));
    bytes4 internal selector3 = bytes4(keccak256("setThird(uint256)"));
    uint48 internal constant TIMELOCK_DELAY = 1 days;
    uint48 internal constant EXECUTION_WINDOW = 7 days;

    function setUp() public {
        queue = new MockTimelockBatchQueue(TIMELOCK_DELAY);
        reentrant = new ReentrantSubAction(address(queue));
    }

    // ===== HELPERS =====

    function _newSubAction(
        address t_,
        bytes4 s_,
        uint256 v_
    ) internal pure returns (ITimelockBatchQueue.BatchAction memory) {
        return ITimelockBatchQueue.BatchAction({target: t_, selector: s_, payload: abi.encode(v_)});
    }

    function _buildBatchOfThree()
        internal
        view
        returns (ITimelockBatchQueue.BatchAction[] memory actions_)
    {
        // Payload encodes the sub-action's index. The mock's `_validateSubAction` decodes it
        // when `rejectSubActionAtIndex` is set, so this gives every batch a uniform "reject at
        // index N" mechanism without writing state from a view hook.
        actions_ = new ITimelockBatchQueue.BatchAction[](3);
        actions_[0] = _newSubAction(target1, selector1, 0);
        actions_[1] = _newSubAction(target2, selector2, 1);
        actions_[2] = _newSubAction(target3, selector3, 2);
    }

    function _buildBatchOfSize(
        uint256 size_
    ) internal pure returns (ITimelockBatchQueue.BatchAction[] memory actions_) {
        actions_ = new ITimelockBatchQueue.BatchAction[](size_);
        for (uint256 i; i < size_; ++i) {
            actions_[i] = ITimelockBatchQueue.BatchAction({
                target: address(uint160(0x1000 + i)),
                selector: bytes4(uint32(0xa0000000 + i)),
                payload: abi.encode(uint256(i))
            });
        }
    }

    function _queueSingleAction() internal returns (uint64) {
        vm.prank(proposer);
        return queue.queueAction(target1, selector1, abi.encode(uint256(11)));
    }

    function _queueThreeBatch()
        internal
        returns (uint64 actionId_, ITimelockBatchQueue.BatchAction[] memory actions_)
    {
        actions_ = _buildBatchOfThree();
        vm.prank(proposer);
        actionId_ = queue.queueBatchAction(actions_);
    }

    function _warpReady(uint64 actionId_, uint256 ts_) internal {
        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId_);
        vm.warp(bound(ts_, a.executableAt, a.expiresAt));
    }

    // =================================================================================
    // CONSTRUCTOR & ERC-165
    // =================================================================================

    // given the queue is deployed
    //  [X] it stores the initial delay and first action id
    function test_constructor_setsInitialState() public view {
        assertEq(queue.timelockDelay(), TIMELOCK_DELAY, "Timelock delay");
        assertEq(queue.nextActionId(), 1, "Next action ID");
    }

    // given the delay is below MIN_DELAY at construction
    //  [X] constructor reverts
    function test_constructor_givenDelayBelowMinimum_reverts() public {
        uint48 invalidDelay = queue.MIN_DELAY() - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                invalidDelay,
                queue.MIN_DELAY(),
                queue.MAX_DELAY()
            )
        );
        new MockTimelockBatchQueue(invalidDelay);
    }

    // given the delay is above MAX_DELAY at construction
    //  [X] constructor reverts
    function test_constructor_givenDelayAboveMaximum_reverts() public {
        uint48 invalidDelay = queue.MAX_DELAY() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                invalidDelay,
                queue.MIN_DELAY(),
                queue.MAX_DELAY()
            )
        );
        new MockTimelockBatchQueue(invalidDelay);
    }

    // given the delay equals MIN_DELAY at construction
    //  [X] constructor succeeds
    function test_constructor_givenDelayAtMinimum_succeeds() public {
        MockTimelockBatchQueue q = new MockTimelockBatchQueue(queue.MIN_DELAY());
        assertEq(q.timelockDelay(), queue.MIN_DELAY(), "Timelock delay");
    }

    // given the delay equals MAX_DELAY at construction
    //  [X] constructor succeeds
    function test_constructor_givenDelayAtMaximum_succeeds() public {
        MockTimelockBatchQueue q = new MockTimelockBatchQueue(queue.MAX_DELAY());
        assertEq(q.timelockDelay(), queue.MAX_DELAY(), "Timelock delay");
    }

    // given a valid delay at construction
    //  [X] constructor emits TimelockDelaySet
    function test_constructor_emitsTimelockDelaySet() public {
        uint48 d = 3 days;
        vm.expectEmit(false, false, false, true);
        emit ITimelockBatchQueue.TimelockDelaySet(d);
        new MockTimelockBatchQueue(d);
    }

    // given the queue is deployed
    //  [X] supportsInterface returns true for IERC165 and ITimelockBatchQueue
    //  [X] supportsInterface returns false for an unrelated interface
    function test_supportsInterface() public view {
        ERC165Helper.validateSupportsInterface(address(queue));
        assertEq(queue.supportsInterface(type(IERC165).interfaceId), true, "IERC165");
        assertEq(
            queue.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            true,
            "ITimelockBatchQueue"
        );
        assertEq(queue.supportsInterface(type(IERC20).interfaceId), false, "IERC20");
    }

    // =================================================================================
    // TIMELOCK DELAY
    // =================================================================================

    // given setTimelockDelay is called with a delay below MIN_DELAY
    //  [X] reverts
    function test_setTimelockDelay_givenDelayBelowMinimum_reverts() public {
        uint48 invalidDelay = queue.MIN_DELAY() - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                invalidDelay,
                queue.MIN_DELAY(),
                queue.MAX_DELAY()
            )
        );
        queue.setTimelockDelay(invalidDelay);
    }

    // given setTimelockDelay is called with a delay above MAX_DELAY
    //  [X] reverts
    function test_setTimelockDelay_givenDelayAboveMaximum_reverts() public {
        uint48 invalidDelay = queue.MAX_DELAY() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                invalidDelay,
                queue.MIN_DELAY(),
                queue.MAX_DELAY()
            )
        );
        queue.setTimelockDelay(invalidDelay);
    }

    // given setTimelockDelay is called with the minimum delay
    //  [X] succeeds, emits TimelockDelaySet, updates state
    function test_setTimelockDelay_atMinimum_succeeds() public {
        uint48 d = queue.MIN_DELAY();
        vm.expectEmit(false, false, false, true);
        emit ITimelockBatchQueue.TimelockDelaySet(d);
        queue.setTimelockDelay(d);
        assertEq(queue.timelockDelay(), d, "Timelock delay");
    }

    // given setTimelockDelay is called with the maximum delay
    //  [X] succeeds, emits TimelockDelaySet, updates state
    function test_setTimelockDelay_atMaximum_succeeds() public {
        uint48 d = queue.MAX_DELAY();
        vm.expectEmit(false, false, false, true);
        emit ITimelockBatchQueue.TimelockDelaySet(d);
        queue.setTimelockDelay(d);
        assertEq(queue.timelockDelay(), d, "Timelock delay");
    }

    // given setTimelockDelay is called with an interior valid delay
    //  [X] succeeds, emits TimelockDelaySet, updates state
    function test_setTimelockDelay_interior_succeeds() public {
        uint48 d = 5 days;
        vm.expectEmit(false, false, false, true);
        emit ITimelockBatchQueue.TimelockDelaySet(d);
        queue.setTimelockDelay(d);
        assertEq(queue.timelockDelay(), d, "Timelock delay");
    }

    // given an action was queued under delay X
    //  given the timelock delay changes to Y != X afterwards
    //   [X] the queued action's executableAt remains queuedAt + X
    function test_setTimelockDelay_doesNotAffectExistingActionExecutableAt() public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory before_ = queue.getQueuedAction(actionId);

        uint48 newDelay = 10 days;
        queue.setTimelockDelay(newDelay);

        ITimelockBatchQueue.QueuedAction memory after_ = queue.getQueuedAction(actionId);
        assertEq(after_.executableAt, before_.executableAt, "executableAt unchanged");
        assertEq(after_.executableAt, before_.queuedAt + TIMELOCK_DELAY, "executableAt formula");
        assertEq(queue.timelockDelay(), newDelay, "delay updated");
    }

    // =================================================================================
    // QUEUE - SINGLE ACTION OVERLOAD
    // =================================================================================

    // given _validateSubAction rejects via the general flag
    //  [X] queueAction reverts
    //  [X] nextActionId is unchanged
    function test_queueAction_givenValidateSubActionRejects_reverts() public {
        queue.setRejectSubAction(true);
        vm.expectRevert(MockTimelockBatchQueue.MockTimelockBatchQueue_SubActionRejected.selector);
        queue.queueAction(target1, selector1, abi.encode(uint256(11)));
        assertEq(queue.nextActionId(), 1, "nextActionId unchanged");
    }

    // given _validateSubAction has a queueCaller restriction
    //  given the caller is not the allowed address
    //   [X] queueAction reverts
    //  given the caller is the allowed address
    //   [X] queueAction succeeds
    function test_queueAction_givenWrongCaller_reverts() public {
        queue.setQueueCaller(proposer);
        vm.expectRevert(MockTimelockBatchQueue.MockTimelockBatchQueue_SubActionRejected.selector);
        vm.prank(executor);
        queue.queueAction(target1, selector1, abi.encode(uint256(11)));
    }

    function test_queueAction_givenAllowedCaller_succeeds() public {
        queue.setQueueCaller(proposer);
        vm.prank(proposer);
        uint64 actionId = queue.queueAction(target1, selector1, abi.encode(uint256(11)));
        assertEq(actionId, 1, "Action ID");
    }

    // given a successful single-action queue
    //  [X] stores correct metadata and a length-1 actions array
    //  [X] emits TimelockActionQueued and one TimelockSubActionQueued
    //  [X] increments nextActionId by one
    function test_queueAction_storesAndEmitsAndCallsHooks() public {
        uint64 expectedId = queue.nextActionId();
        bytes memory payload = abi.encode(uint256(11));
        uint48 queuedAt = uint48(vm.getBlockTimestamp());
        uint48 executableAt = queuedAt + TIMELOCK_DELAY;
        uint48 expiresAt = executableAt + EXECUTION_WINDOW;

        ITimelockBatchQueue.BatchAction[]
            memory expectedActions = new ITimelockBatchQueue.BatchAction[](1);
        expectedActions[0] = ITimelockBatchQueue.BatchAction({
            target: target1,
            selector: selector1,
            payload: payload
        });
        bytes32 expectedHash = keccak256(abi.encode(expectedActions));

        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionQueued(
            expectedId,
            proposer,
            expectedHash,
            executableAt,
            expiresAt
        );
        vm.expectEmit(true, true, true, true);
        emit ITimelockBatchQueue.TimelockSubActionQueued(
            expectedId,
            target1,
            selector1,
            0,
            keccak256(payload)
        );

        vm.prank(proposer);
        uint64 actionId = queue.queueAction(target1, selector1, payload);

        assertEq(actionId, expectedId, "Action ID");
        assertEq(queue.nextActionId(), expectedId + 1, "Next action ID");

        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        assertEq(a.proposer, proposer, "proposer");
        assertEq(a.queuedAt, queuedAt, "queuedAt");
        assertEq(a.executableAt, executableAt, "executableAt");
        assertEq(a.expiresAt, expiresAt, "expiresAt");
        assertEq(a.executed, false, "executed");
        assertEq(a.cancelled, false, "cancelled");
        assertEq(a.actions.length, 1, "actions length");
        assertEq(a.actions[0].target, target1, "target");
        assertEq(a.actions[0].selector, selector1, "selector");
        assertEq(a.actions[0].payload, payload, "payload");
    }

    // =================================================================================
    // QUEUE - BATCH OVERLOAD
    // =================================================================================

    // given the batch is empty
    //  [X] reverts BatchEmpty before any hook is called
    //  [X] nextActionId unchanged
    function test_queueBatchAction_givenEmpty_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](0);
        vm.expectRevert(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector);
        queue.queueBatchAction(actions);
        assertEq(queue.nextActionId(), 1, "nextActionId unchanged");
    }

    // given the batch exceeds the default _maxBatchSize (15) by one
    //  [X] reverts BatchTooLarge(16, 15) before any validation hook fires
    function test_queueBatchAction_givenAboveDefaultMax_reverts() public {
        uint256 max = queue.getMaxBatchSize();
        ITimelockBatchQueue.BatchAction[] memory actions = _buildBatchOfSize(max + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_BatchTooLarge.selector,
                max + 1,
                max
            )
        );
        queue.queueBatchAction(actions);
        assertEq(queue.nextActionId(), 1, "nextActionId unchanged");
    }

    // given the batch exceeds an overridden _maxBatchSize by one
    //  [X] reverts BatchTooLarge(N+1, N)
    function test_queueBatchAction_givenAboveOverrideMax_reverts() public {
        queue.setMaxBatchSizeOverride(3);
        ITimelockBatchQueue.BatchAction[] memory actions = _buildBatchOfSize(4);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_BatchTooLarge.selector,
                uint256(4),
                uint256(3)
            )
        );
        queue.queueBatchAction(actions);
    }

    // given the batch equals the default _maxBatchSize exactly
    //  [X] succeeds
    function test_queueBatchAction_atDefaultMax_succeeds() public {
        uint256 max = queue.getMaxBatchSize();
        ITimelockBatchQueue.BatchAction[] memory actions = _buildBatchOfSize(max);
        vm.prank(proposer);
        uint64 actionId = queue.queueBatchAction(actions);
        assertEq(actionId, 1, "Action ID");
        assertEq(queue.getQueuedActionLength(actionId), max, "Stored length");
    }

    // given the batch equals an overridden _maxBatchSize exactly
    //  [X] succeeds
    function test_queueBatchAction_atOverrideMax_succeeds() public {
        queue.setMaxBatchSizeOverride(3);
        ITimelockBatchQueue.BatchAction[] memory actions = _buildBatchOfSize(3);
        vm.prank(proposer);
        uint64 actionId = queue.queueBatchAction(actions);
        assertEq(actionId, 1, "Action ID");
        assertEq(queue.getQueuedActionLength(actionId), 3, "Stored length");
    }

    // given _validateSubAction rejects at index i
    //  [X] reverts at that index (verified via the index encoded in the mock error)
    //  [X] _validateBatch is not called (revert error is from _validateSubAction)
    //  [X] no state stored (action does not exist, nextActionId unchanged)
    function test_queueBatchAction_givenValidateSubActionRejectsAtIndex_reverts() public {
        uint256 rejectIndex = 1;
        queue.setRejectSubActionAtIndex(rejectIndex);
        ITimelockBatchQueue.BatchAction[] memory actions = _buildBatchOfThree();
        uint64 expectedId = queue.nextActionId();

        vm.expectRevert(
            abi.encodeWithSelector(
                MockTimelockBatchQueue.MockTimelockBatchQueue_SubActionRejectedAt.selector,
                rejectIndex
            )
        );
        queue.queueBatchAction(actions);

        // No state stored
        assertEq(queue.nextActionId(), expectedId, "nextActionId unchanged");
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                expectedId
            )
        );
        queue.getQueuedAction(expectedId);
    }

    // given _validateBatch rejects after all _validateSubAction calls succeeded
    //  [X] reverts BatchRejected
    //  [X] no state stored
    function test_queueBatchAction_givenValidateBatchRejects_reverts() public {
        queue.setRejectBatch(true);
        ITimelockBatchQueue.BatchAction[] memory actions = _buildBatchOfThree();
        uint64 expectedId = queue.nextActionId();

        vm.expectRevert(MockTimelockBatchQueue.MockTimelockBatchQueue_BatchRejected.selector);
        queue.queueBatchAction(actions);

        assertEq(queue.nextActionId(), expectedId, "nextActionId unchanged");
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                expectedId
            )
        );
        queue.getQueuedAction(expectedId);
    }

    // given a successful 3-element batch is queued
    //  [X] all sub-actions stored in order
    //  [X] one TimelockActionQueued then exactly 3 TimelockSubActionQueued in increasing index order
    //  [X] nextActionId increments by exactly one for the whole batch
    function test_queueBatchAction_storesAndEmitsAndCallsHooks() public {
        uint64 expectedId = queue.nextActionId();
        ITimelockBatchQueue.BatchAction[] memory actions = _buildBatchOfThree();
        bytes32 expectedHash = keccak256(abi.encode(actions));
        uint48 queuedAt = uint48(vm.getBlockTimestamp());
        uint48 executableAt = queuedAt + TIMELOCK_DELAY;
        uint48 expiresAt = executableAt + EXECUTION_WINDOW;

        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionQueued(
            expectedId,
            proposer,
            expectedHash,
            executableAt,
            expiresAt
        );
        for (uint256 i; i < 3; ++i) {
            vm.expectEmit(true, true, true, true);
            emit ITimelockBatchQueue.TimelockSubActionQueued(
                expectedId,
                actions[i].target,
                actions[i].selector,
                i,
                keccak256(actions[i].payload)
            );
        }

        vm.prank(proposer);
        uint64 actionId = queue.queueBatchAction(actions);

        assertEq(actionId, expectedId, "Action ID");
        assertEq(queue.nextActionId(), expectedId + 1, "Next action ID");

        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        assertEq(a.actions.length, 3, "actions length");
        for (uint256 i; i < 3; ++i) {
            assertEq(a.actions[i].target, actions[i].target, "target i");
            assertEq(a.actions[i].selector, actions[i].selector, "selector i");
            assertEq(a.actions[i].payload, actions[i].payload, "payload i");
        }
    }

    // given a 5-element batch is queued
    //  [X] nextActionId increments by exactly one (not five)
    function test_queueBatchAction_nextActionIdIncrementsByOne() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _buildBatchOfSize(5);
        uint64 before_ = queue.nextActionId();
        vm.prank(proposer);
        queue.queueBatchAction(actions);
        assertEq(queue.nextActionId(), before_ + 1, "nextActionId += 1");
    }

    // =================================================================================
    // _maxBatchSize DEFAULT
    // =================================================================================

    // given the contract uses the base default _maxBatchSize
    //  [X] returns 15
    function test_maxBatchSize_defaultIs15() public view {
        assertEq(queue.getMaxBatchSize(), 15, "Default max batch size");
    }

    // =================================================================================
    // getQueuedAction
    // =================================================================================

    // given an action does not exist
    //  [X] getQueuedAction reverts ActionNotFound
    function test_getQueuedAction_givenNonExistent_reverts(uint64 id_) public {
        vm.assume(id_ != 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        queue.getQueuedAction(id_);
    }

    // given an action was just queued
    //  [X] getQueuedAction returns full metadata and full actions array
    function test_getQueuedAction_afterQueue_returnsAll() public {
        (uint64 actionId, ITimelockBatchQueue.BatchAction[] memory actions) = _queueThreeBatch();
        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        assertEq(a.actions.length, 3, "length");
        for (uint256 i; i < 3; ++i) {
            assertEq(a.actions[i].target, actions[i].target, "target");
        }
    }

    // given an action has been executed
    //  [X] getQueuedAction returns metadata with executed=true and empty actions
    function test_getQueuedAction_afterExecute_returnsClearedActions() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId, type(uint256).max);
        queue.executeQueuedAction(actionId);
        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        assertEq(a.executed, true, "executed");
        assertEq(a.cancelled, false, "cancelled");
        assertEq(a.actions.length, 0, "actions cleared");
        assertEq(a.proposer, proposer, "proposer retained");
    }

    // given an action has been cancelled
    //  [X] getQueuedAction returns metadata with cancelled=true and empty actions
    function test_getQueuedAction_afterCancel_returnsClearedActions() public {
        uint64 actionId = _queueSingleAction();
        queue.cancelQueuedAction(actionId);
        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        assertEq(a.executed, false, "executed");
        assertEq(a.cancelled, true, "cancelled");
        assertEq(a.actions.length, 0, "actions cleared");
        assertEq(a.proposer, proposer, "proposer retained");
    }

    // =================================================================================
    // getQueuedActionLength
    // =================================================================================

    // given an action does not exist
    //  [X] getQueuedActionLength reverts ActionNotFound
    function test_getQueuedActionLength_givenNonExistent_reverts(uint64 id_) public {
        vm.assume(id_ != 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        queue.getQueuedActionLength(id_);
    }

    // given a single action was queued
    //  [X] getQueuedActionLength returns 1
    function test_getQueuedActionLength_givenSingleQueued_returnsOne() public {
        uint64 actionId = _queueSingleAction();
        assertEq(queue.getQueuedActionLength(actionId), 1, "Length");
    }

    // given a 3-element batch was queued
    //  [X] getQueuedActionLength returns 3
    function test_getQueuedActionLength_givenBatchQueued_returnsBatchSize() public {
        (uint64 actionId, ) = _queueThreeBatch();
        assertEq(queue.getQueuedActionLength(actionId), 3, "Length");
    }

    // given an action has been executed
    //  [X] getQueuedActionLength reverts ActionAlreadyExecuted
    function test_getQueuedActionLength_givenExecuted_revertsAlreadyExecuted() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId, type(uint256).max);
        queue.executeQueuedAction(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.getQueuedActionLength(actionId);
    }

    // given an action has been cancelled
    //  [X] getQueuedActionLength reverts ActionCancelled
    function test_getQueuedActionLength_givenCancelled_revertsCancelled() public {
        uint64 actionId = _queueSingleAction();
        queue.cancelQueuedAction(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        queue.getQueuedActionLength(actionId);
    }

    // =================================================================================
    // getQueuedSubAction
    // =================================================================================

    // given an action does not exist
    //  [X] getQueuedSubAction reverts ActionNotFound
    function test_getQueuedSubAction_givenNonExistent_reverts(uint64 id_) public {
        vm.assume(id_ != 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        queue.getQueuedSubAction(id_, 0);
    }

    // given a 3-element batch was queued
    //  [X] each (target, selector, payload) is returned correctly per index
    function test_getQueuedSubAction_givenBatchQueued_returnsEach() public {
        (uint64 actionId, ITimelockBatchQueue.BatchAction[] memory actions) = _queueThreeBatch();
        for (uint256 i; i < 3; ++i) {
            (address t, bytes4 s, bytes memory p) = queue.getQueuedSubAction(actionId, i);
            assertEq(t, actions[i].target, "target");
            assertEq(s, actions[i].selector, "selector");
            assertEq(p, actions[i].payload, "payload");
        }
    }

    // given a 3-element batch was queued
    //  [X] getQueuedSubAction reverts at index == length
    //  [X] getQueuedSubAction reverts at an index far above length
    function test_getQueuedSubAction_givenIndexAtLength_reverts() public {
        (uint64 actionId, ) = _queueThreeBatch();
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_SubActionIndexOutOfBounds.selector,
                actionId,
                uint256(3),
                uint256(3)
            )
        );
        queue.getQueuedSubAction(actionId, 3);
    }

    function test_getQueuedSubAction_givenIndexFarAbove_reverts() public {
        (uint64 actionId, ) = _queueThreeBatch();
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_SubActionIndexOutOfBounds.selector,
                actionId,
                uint256(99),
                uint256(3)
            )
        );
        queue.getQueuedSubAction(actionId, 99);
    }

    // given an action has been executed
    //  [X] getQueuedSubAction reverts ActionAlreadyExecuted for any index
    function test_getQueuedSubAction_givenExecuted_revertsAlreadyExecuted() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId, type(uint256).max);
        queue.executeQueuedAction(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.getQueuedSubAction(actionId, 0);
    }

    // given an action has been cancelled
    //  [X] getQueuedSubAction reverts ActionCancelled for any index
    function test_getQueuedSubAction_givenCancelled_revertsCancelled() public {
        uint64 actionId = _queueSingleAction();
        queue.cancelQueuedAction(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        queue.getQueuedSubAction(actionId, 0);
    }

    // =================================================================================
    // EXECUTE - PRECONDITIONS
    // =================================================================================

    // given an action does not exist
    //  [X] executeQueuedAction reverts ActionNotFound
    function test_executeQueuedAction_givenNonExistent_reverts(uint64 id_) public {
        vm.assume(id_ != 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        queue.executeQueuedAction(id_);
    }

    // given an action was queued
    //  given the timelock has not yet elapsed (any timestamp in [queuedAt, executableAt - 1])
    //   [X] executeQueuedAction reverts ActionNotReady
    function test_executeQueuedAction_givenBeforeReady_reverts(uint256 ts_) public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        vm.warp(bound(ts_, a.queuedAt, a.executableAt - 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotReady.selector,
                actionId,
                a.executableAt
            )
        );
        queue.executeQueuedAction(actionId);
    }

    // given an action was queued
    //  given the expiry has passed (any timestamp in [expiresAt + 1, type(uint48).max])
    //   [X] executeQueuedAction reverts ActionExpired
    function test_executeQueuedAction_givenAfterExpiry_reverts(uint256 ts_) public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        vm.warp(bound(ts_, uint256(a.expiresAt) + 1, type(uint48).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionExpired.selector,
                actionId,
                a.expiresAt
            )
        );
        queue.executeQueuedAction(actionId);
    }

    // given the timestamp is exactly executableAt
    //  [X] executeQueuedAction succeeds
    function test_executeQueuedAction_atExecutableAtBoundary_succeeds() public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        vm.warp(a.executableAt);
        queue.executeQueuedAction(actionId);
        assertEq(queue.getQueuedAction(actionId).executed, true, "executed");
    }

    // given the timestamp is exactly expiresAt
    //  [X] executeQueuedAction succeeds (boundary inclusive)
    function test_executeQueuedAction_atExpiresAtBoundary_succeeds() public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        vm.warp(a.expiresAt);
        queue.executeQueuedAction(actionId);
        assertEq(queue.getQueuedAction(actionId).executed, true, "executed");
    }

    // given an action has been executed
    //  [X] executeQueuedAction reverts ActionAlreadyExecuted
    function test_executeQueuedAction_givenExecuted_revertsAlreadyExecuted() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId, type(uint256).max);
        queue.executeQueuedAction(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.executeQueuedAction(actionId);
    }

    // given an action has been cancelled
    //  [X] executeQueuedAction reverts ActionCancelled
    function test_executeQueuedAction_givenCancelled_revertsCancelled() public {
        uint64 actionId = _queueSingleAction();
        queue.cancelQueuedAction(actionId);
        vm.warp(queue.getQueuedAction(actionId).executableAt);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        queue.executeQueuedAction(actionId);
    }

    // given _validateExecution rejects
    //  [X] executeQueuedAction reverts
    //  [X] action.executed remains false
    //  [X] actions array retained (verified by getQueuedActionLength still returning the original length)
    function test_executeQueuedAction_givenValidateExecutionRejects_reverts() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId, type(uint256).max);
        queue.setRejectExecution(true);
        vm.expectRevert(MockTimelockBatchQueue.MockTimelockBatchQueue_ExecutionRejected.selector);
        queue.executeQueuedAction(actionId);

        assertEq(queue.getQueuedAction(actionId).executed, false, "executed false");
        assertEq(queue.getQueuedActionLength(actionId), 1, "actions retained");
    }

    // given _validateExecution has an executionCaller restriction
    //  given the caller is not the allowed address
    //   [X] executeQueuedAction reverts
    function test_executeQueuedAction_givenWrongExecutionCaller_reverts() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId, type(uint256).max);
        queue.setExecutionCaller(executor);
        vm.expectRevert(MockTimelockBatchQueue.MockTimelockBatchQueue_ExecutionRejected.selector);
        vm.prank(address(0xBADBAD));
        queue.executeQueuedAction(actionId);
    }

    // =================================================================================
    // EXECUTE - HAPPY PATHS
    // =================================================================================

    // given a single-action queue is ready
    //  [X] _executeSubAction is called once with (actionId, 0, action)
    //  [X] one TimelockSubActionExecuted then TimelockActionExecuted emitted, in order
    //  [X] action.executed = true and actions cleared
    //  [X] executedValues records the decoded payload
    function test_executeQueuedAction_singleAction_succeeds() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId, type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit ITimelockBatchQueue.TimelockSubActionExecuted(actionId, target1, selector1, 0);
        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionExecuted(actionId, executor);

        vm.prank(executor);
        queue.executeQueuedAction(actionId);

        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        assertEq(a.executed, true, "executed");
        assertEq(a.actions.length, 0, "actions cleared");

        uint256[] memory vals = queue.getExecutedValues();
        assertEq(vals.length, 1, "executedValues length");
        assertEq(vals[0], 11, "executedValues[0]");

        MockTimelockBatchQueue.ExecuteSubActionCall[] memory calls = queue
            .getExecuteSubActionCalls();
        assertEq(calls.length, 1, "execute calls length");
        assertEq(calls[0].actionId, actionId, "call actionId");
        assertEq(calls[0].index, 0, "call index");
        assertEq(calls[0].target, target1, "call target");
        assertEq(calls[0].selector, selector1, "call selector");
    }

    // given a 3-element batch is ready
    //  [X] three TimelockSubActionExecuted (in order) then one TimelockActionExecuted
    //  [X] _executeSubAction called 3 times in order with the correct args per index
    //  [X] executedValues == [v0, v1, v2] in input order
    function test_executeQueuedAction_batch_succeeds() public {
        (uint64 actionId, ITimelockBatchQueue.BatchAction[] memory actions) = _queueThreeBatch();
        _warpReady(actionId, type(uint256).max);

        for (uint256 i; i < 3; ++i) {
            vm.expectEmit(true, true, true, true);
            emit ITimelockBatchQueue.TimelockSubActionExecuted(
                actionId,
                actions[i].target,
                actions[i].selector,
                i
            );
        }
        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionExecuted(actionId, executor);

        vm.prank(executor);
        queue.executeQueuedAction(actionId);

        uint256[] memory vals = queue.getExecutedValues();
        assertEq(vals.length, 3, "executedValues length");
        assertEq(vals[0], 0, "v0");
        assertEq(vals[1], 1, "v1");
        assertEq(vals[2], 2, "v2");

        MockTimelockBatchQueue.ExecuteSubActionCall[] memory calls = queue
            .getExecuteSubActionCalls();
        assertEq(calls.length, 3, "execute calls length");
        for (uint256 i; i < 3; ++i) {
            assertEq(calls[i].actionId, actionId, "call actionId i");
            assertEq(calls[i].index, i, "call index i");
            assertEq(calls[i].target, actions[i].target, "call target i");
            assertEq(calls[i].selector, actions[i].selector, "call selector i");
            assertEq(calls[i].payloadHash, keccak256(actions[i].payload), "call payloadHash i");
        }
    }

    // =================================================================================
    // CANCEL
    // =================================================================================

    // given an action does not exist
    //  [X] cancelQueuedAction reverts ActionNotFound
    function test_cancelQueuedAction_givenNonExistent_reverts(uint64 id_) public {
        vm.assume(id_ != 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionNotFound.selector,
                id_
            )
        );
        queue.cancelQueuedAction(id_);
    }

    // given an action has been executed
    //  [X] cancelQueuedAction reverts ActionAlreadyExecuted
    function test_cancelQueuedAction_givenExecuted_revertsAlreadyExecuted() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId, type(uint256).max);
        queue.executeQueuedAction(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.cancelQueuedAction(actionId);
    }

    // given an action has been cancelled
    //  [X] cancelQueuedAction reverts ActionCancelled
    function test_cancelQueuedAction_givenCancelled_revertsCancelled() public {
        uint64 actionId = _queueSingleAction();
        queue.cancelQueuedAction(actionId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionCancelled.selector,
                actionId
            )
        );
        queue.cancelQueuedAction(actionId);
    }

    // given _validateCancellation rejects
    //  [X] cancelQueuedAction reverts
    //  [X] action.cancelled remains false
    //  [X] actions retained
    function test_cancelQueuedAction_givenValidateCancellationRejects_reverts() public {
        uint64 actionId = _queueSingleAction();
        queue.setRejectCancellation(true);
        vm.expectRevert(
            MockTimelockBatchQueue.MockTimelockBatchQueue_CancellationRejected.selector
        );
        queue.cancelQueuedAction(actionId);
        assertEq(queue.getQueuedAction(actionId).cancelled, false, "cancelled false");
        assertEq(queue.getQueuedActionLength(actionId), 1, "actions retained");
    }

    // given a single-action queue
    //  [X] cancelQueuedAction emits TimelockActionCancelled, sets cancelled, clears actions
    function test_cancelQueuedAction_single_succeeds(address canceller_) public {
        vm.assume(canceller_ != address(0));
        uint64 actionId = _queueSingleAction();
        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionCancelled(actionId, canceller_);
        vm.prank(canceller_);
        queue.cancelQueuedAction(actionId);
        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        assertEq(a.cancelled, true, "cancelled");
        assertEq(a.actions.length, 0, "actions cleared");
    }

    // given a 3-element batch
    //  [X] cancelQueuedAction emits TimelockActionCancelled, sets cancelled, clears actions
    function test_cancelQueuedAction_batch_succeeds(address canceller_) public {
        vm.assume(canceller_ != address(0));
        (uint64 actionId, ) = _queueThreeBatch();
        vm.expectEmit(true, true, false, true);
        emit ITimelockBatchQueue.TimelockActionCancelled(actionId, canceller_);
        vm.prank(canceller_);
        queue.cancelQueuedAction(actionId);
        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        assertEq(a.cancelled, true, "cancelled");
        assertEq(a.actions.length, 0, "actions cleared");
    }

    // given an action is past executableAt but not yet expired
    //  [X] cancelQueuedAction succeeds (cancellation is not blocked by readiness)
    function test_cancelQueuedAction_afterExecutableAt_succeeds() public {
        uint64 actionId = _queueSingleAction();
        _warpReady(actionId, type(uint256).max);
        queue.cancelQueuedAction(actionId);
        assertEq(queue.getQueuedAction(actionId).cancelled, true, "cancelled");
    }

    // given an action is past expiresAt
    //  [X] cancelQueuedAction succeeds (expired actions can still be cancelled)
    function test_cancelQueuedAction_afterExpiresAt_succeeds() public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory a = queue.getQueuedAction(actionId);
        vm.warp(uint256(a.expiresAt) + 1);
        queue.cancelQueuedAction(actionId);
        assertEq(queue.getQueuedAction(actionId).cancelled, true, "cancelled");
    }

    // given a cancellationCaller restriction
    //  given the caller is not the allowed address
    //   [X] cancelQueuedAction reverts
    function test_cancelQueuedAction_givenWrongCancellationCaller_reverts() public {
        uint64 actionId = _queueSingleAction();
        queue.setCancellationCaller(canceller);
        vm.expectRevert(
            MockTimelockBatchQueue.MockTimelockBatchQueue_CancellationRejected.selector
        );
        vm.prank(address(0xBADBAD));
        queue.cancelQueuedAction(actionId);
    }

    // =================================================================================
    // RE-ENTRANCY
    // =================================================================================

    // given a single-action batch with target = reentrant contract
    //  given the reentrant contract is armed to call executeQueuedAction(sameId)
    //   [X] outer execute reverts ActionAlreadyExecuted (executed flag set before loop)
    function test_reentrancy_executeReenter_reverts() public {
        // queue an action targeted at the reentrant contract
        bytes memory payload = hex"01"; // arbitrary; reentrant fallback ignores it
        vm.prank(proposer);
        uint64 actionId = queue.queueAction(address(reentrant), selector1, payload);
        _warpReady(actionId, type(uint256).max);

        // arm the reentrant to call executeQueuedAction(actionId) on inner trigger
        reentrant.arm(abi.encodeCall(TimelockBatchQueue.executeQueuedAction, (actionId)));
        // route mock's _executeSubAction to actually call the target
        queue.setCallThroughTarget(address(reentrant));

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.executeQueuedAction(actionId);
    }

    // given a single-action batch with target = reentrant contract
    //  given the reentrant contract is armed to call cancelQueuedAction(sameId)
    //   [X] outer execute reverts ActionAlreadyExecuted (cancel sees executed flag set before loop)
    function test_reentrancy_cancelDuringExecute_revertsAlreadyExecuted() public {
        bytes memory payload = hex"01";
        vm.prank(proposer);
        uint64 actionId = queue.queueAction(address(reentrant), selector1, payload);
        _warpReady(actionId, type(uint256).max);

        reentrant.arm(abi.encodeCall(TimelockBatchQueue.cancelQueuedAction, (actionId)));
        queue.setCallThroughTarget(address(reentrant));

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.executeQueuedAction(actionId);
    }

    // given a single-action batch with target = reentrant contract
    //  given the reentrant contract is armed to queue a NEW action via queueAction
    //   [X] outer execute succeeds and the new action exists at nextActionId
    function test_reentrancy_queueDuringExecute_succeeds() public {
        bytes memory payload = hex"01";
        vm.prank(proposer);
        uint64 outerId = queue.queueAction(address(reentrant), selector1, payload);
        _warpReady(outerId, type(uint256).max);

        uint64 expectedNewId = queue.nextActionId(); // id the inner queue will receive
        reentrant.arm(
            abi.encodeCall(
                MockTimelockBatchQueue.queueAction,
                (target1, selector1, abi.encode(uint256(99)))
            )
        );
        queue.setCallThroughTarget(address(reentrant));

        queue.executeQueuedAction(outerId);

        // outer action is executed
        assertEq(queue.getQueuedAction(outerId).executed, true, "outer executed");

        // new action exists at the expected id
        ITimelockBatchQueue.QueuedAction memory inner = queue.getQueuedAction(expectedNewId);
        assertEq(inner.actions.length, 1, "inner actions length");
        assertEq(inner.actions[0].target, target1, "inner target");
        assertEq(inner.actions[0].selector, selector1, "inner selector");
        assertEq(inner.actions[0].payload, abi.encode(uint256(99)), "inner payload");
        assertEq(queue.nextActionId(), expectedNewId + 1, "nextActionId advanced past inner");
    }
}
