// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ITimelockQueue} from "src/policies/interfaces/utils/ITimelockQueue.sol";
import {TimelockQueue} from "src/policies/utils/TimelockQueue.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

contract MockTimelockQueue is TimelockQueue {
    error MockTimelockQueue_QueueRejected();
    error MockTimelockQueue_ExecutionRejected();
    error MockTimelockQueue_CancellationRejected();
    error MockTimelockQueue_ExecuteActionReverted();

    uint48 public constant MIN_DELAY = 1 days;
    uint48 public constant MAX_DELAY = 30 days;

    uint48 public executionWindow = 7 days;
    uint256 public executedValue;
    address public queueCaller;
    address public executionCaller;
    address public cancellationCaller;
    bool public rejectQueue;
    bool public rejectExecution;
    bool public rejectCancellation;
    bool public revertExecuteAction;

    constructor(uint48 initialTimelockDelay_) TimelockQueue(initialTimelockDelay_) {}

    function queueAction(
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) external returns (uint64 actionId_) {
        return _queueAction(target_, selector_, payload_);
    }

    function setTimelockDelay(uint48 delay_) external {
        _setTimelockDelay(delay_);
    }

    function setExecutionWindow(uint48 executionWindow_) external {
        executionWindow = executionWindow_;
    }

    function setRejectQueue(bool rejectQueue_) external {
        rejectQueue = rejectQueue_;
    }

    function setRejectExecution(bool rejectExecution_) external {
        rejectExecution = rejectExecution_;
    }

    function setRejectCancellation(bool rejectCancellation_) external {
        rejectCancellation = rejectCancellation_;
    }

    function setRevertExecuteAction(bool revertExecuteAction_) external {
        revertExecuteAction = revertExecuteAction_;
    }

    function _validateQueue(address caller_, address, bytes4, bytes memory) internal view override {
        if (rejectQueue) revert MockTimelockQueue_QueueRejected();
        if (queueCaller != address(0) && caller_ != queueCaller)
            revert MockTimelockQueue_QueueRejected();
    }

    function _validateExecution(
        address caller_,
        uint64,
        ITimelockQueue.QueuedAction memory
    ) internal view override {
        if (rejectExecution) revert MockTimelockQueue_ExecutionRejected();
        if (executionCaller != address(0) && caller_ != executionCaller)
            revert MockTimelockQueue_ExecutionRejected();
    }

    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockQueue.QueuedAction memory
    ) internal view override {
        if (rejectCancellation) revert MockTimelockQueue_CancellationRejected();
        if (cancellationCaller != address(0) && caller_ != cancellationCaller)
            revert MockTimelockQueue_CancellationRejected();
    }

    function _executeAction(uint64, ITimelockQueue.QueuedAction memory action_) internal override {
        if (revertExecuteAction) revert MockTimelockQueue_ExecuteActionReverted();

        executedValue = abi.decode(action_.payload, (uint256));
    }

    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ < MIN_DELAY || delay_ > MAX_DELAY)
            revert ITimelockQueue_TimelockDelayInvalid(delay_, MIN_DELAY, MAX_DELAY);
    }

    function _executionWindow() internal view override returns (uint48 executionWindow_) {
        return executionWindow;
    }
}

contract TimelockQueueTest is Test {
    MockTimelockQueue internal queue;

    address internal proposer = address(0x1111);
    address internal executor = address(0x2222);
    address internal canceller = address(0x3333);
    address internal target = address(0x4444);
    bytes4 internal selector = bytes4(keccak256("setValue(uint256)"));
    uint48 internal constant TIMELOCK_DELAY = 1 days;
    uint48 internal constant EXECUTION_WINDOW = 7 days;

    function setUp() public {
        queue = new MockTimelockQueue(TIMELOCK_DELAY);
    }

    function _queueAction() internal returns (uint64 actionId_) {
        vm.prank(proposer);
        return queue.queueAction(target, selector, abi.encode(uint256(11)));
    }

    function _warpReady(uint64 actionId_, uint256 warpedTimestamp_) internal {
        ITimelockQueue.QueuedAction memory action = queue.getQueuedAction(actionId_);
        uint256 readyTimestamp = bound(warpedTimestamp_, action.executableAt, action.expiresAt);
        vm.warp(readyTimestamp);
    }

    // given the timelock queue is deployed
    //  [X] it stores the initial delay and first action id
    //  [X] it supports the timelock queue interface
    function test_constructor_setsInitialState() public view {
        assertEq(queue.timelockDelay(), TIMELOCK_DELAY, "Timelock delay");
        assertEq(queue.nextActionId(), 1, "Next action ID");
    }

    function test_supportsInterface() public view {
        ERC165Helper.validateSupportsInterface(address(queue));
        assertEq(queue.supportsInterface(type(IERC165).interfaceId), true, "IERC165");
        assertEq(queue.supportsInterface(type(ITimelockQueue).interfaceId), true, "ITimelockQueue");
        assertEq(queue.supportsInterface(type(IERC20).interfaceId), false, "IERC20");
    }

    // given the delay is outside the accepted range
    //  [X] constructor reverts
    //  [X] setTimelockDelay reverts
    function test_constructor_givenDelayBelowMinimum_reverts() public {
        uint48 invalidDelay = queue.MIN_DELAY() - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockQueue.ITimelockQueue_TimelockDelayInvalid.selector,
                invalidDelay,
                queue.MIN_DELAY(),
                queue.MAX_DELAY()
            )
        );
        new MockTimelockQueue(invalidDelay);
    }

    function test_setTimelockDelay_givenDelayAboveMaximum_reverts() public {
        uint48 invalidDelay = queue.MAX_DELAY() + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockQueue.ITimelockQueue_TimelockDelayInvalid.selector,
                invalidDelay,
                queue.MIN_DELAY(),
                queue.MAX_DELAY()
            )
        );
        queue.setTimelockDelay(invalidDelay);
    }

    function test_setTimelockDelay_givenDelayIsValid_succeeds() public {
        uint48 newDelay = 2 days;

        vm.expectEmit(false, false, false, true);
        emit ITimelockQueue.TimelockDelaySet(newDelay);

        queue.setTimelockDelay(newDelay);

        assertEq(queue.timelockDelay(), newDelay, "Timelock delay");
    }

    // given _validateQueue rejects
    //  [X] queueAction reverts without storing an action
    // given _validateQueue accepts
    //  [X] queueAction stores expected metadata and payload
    function test_queueAction_givenValidateQueueRejects_reverts() public {
        queue.setRejectQueue(true);

        vm.expectRevert(MockTimelockQueue.MockTimelockQueue_QueueRejected.selector);
        queue.queueAction(target, selector, abi.encode(uint256(11)));

        assertEq(queue.nextActionId(), 1, "Next action ID");
    }

    function test_queueAction_storesExpectedAction() public {
        uint64 expectedActionId = queue.nextActionId();
        bytes memory payload = abi.encode(uint256(11));
        uint48 queuedAt = uint48(block.timestamp);
        uint48 executableAt = queuedAt + queue.timelockDelay();
        uint48 expiresAt = executableAt + EXECUTION_WINDOW;

        vm.expectEmit(true, true, true, true);
        emit ITimelockQueue.TimelockActionQueued(
            expectedActionId,
            target,
            selector,
            proposer,
            keccak256(payload),
            executableAt,
            expiresAt
        );

        vm.prank(proposer);
        uint64 actionId = queue.queueAction(target, selector, payload);

        assertEq(actionId, expectedActionId, "Action ID");
        assertEq(queue.nextActionId(), expectedActionId + 1, "Next action ID");

        ITimelockQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        assertEq(action.target, target, "Target");
        assertEq(action.selector, selector, "Selector");
        assertEq(action.proposer, proposer, "Proposer");
        assertEq(action.queuedAt, queuedAt, "Queued at");
        assertEq(action.executableAt, executableAt, "Executable at");
        assertEq(action.expiresAt, expiresAt, "Expires at");
        assertEq(action.executed, false, "Executed");
        assertEq(action.cancelled, false, "Cancelled");
        assertEq(action.payload, payload, "Payload");
    }

    // given an action has not been queued
    //  [X] getQueuedAction reverts
    //  [X] executeQueuedAction reverts
    function test_getQueuedAction_givenActionDoesNotExist_reverts(uint64 actionId_) public {
        vm.assume(actionId_ != 0);

        vm.expectRevert(
            abi.encodeWithSelector(ITimelockQueue.ITimelockQueue_ActionNotFound.selector, actionId_)
        );
        queue.getQueuedAction(actionId_);
    }

    function test_executeQueuedAction_givenActionDoesNotExist_reverts(uint64 actionId_) public {
        vm.assume(actionId_ != 0);

        vm.expectRevert(
            abi.encodeWithSelector(ITimelockQueue.ITimelockQueue_ActionNotFound.selector, actionId_)
        );
        queue.executeQueuedAction(actionId_);
    }

    // given an action has been queued
    //  given the timelock delay has not been reached
    //   [X] executeQueuedAction reverts for any timestamp before executableAt
    //  given the timelock has passed
    //   given the expiry has not been reached
    //    [X] executeQueuedAction succeeds and clears payload
    //  given the expiry has passed
    //   [X] executeQueuedAction reverts for any timestamp after expiresAt
    function test_executeQueuedAction_beforeDelay_reverts(uint256 warpedTimestamp_) public {
        uint64 actionId = _queueAction();
        ITimelockQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        uint256 timestamp = bound(warpedTimestamp_, action.queuedAt, action.executableAt - 1);
        vm.warp(timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockQueue.ITimelockQueue_ActionNotReady.selector,
                actionId,
                action.executableAt
            )
        );
        queue.executeQueuedAction(actionId);
    }

    function test_executeQueuedAction_ready_succeeds(
        uint256 warpedTimestamp_,
        address executor_
    ) public {
        uint64 actionId = _queueAction();
        _warpReady(actionId, warpedTimestamp_);

        vm.expectEmit(true, true, true, true);
        emit ITimelockQueue.TimelockActionExecuted(actionId, target, selector, executor_);

        vm.prank(executor_);
        queue.executeQueuedAction(actionId);

        assertEq(queue.executedValue(), 11, "Executed value");

        ITimelockQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        assertEq(action.executed, true, "Executed");
        assertEq(action.payload.length, 0, "Payload cleared");
    }

    function test_executeQueuedAction_afterExpiry_reverts(uint256 warpedTimestamp_) public {
        uint64 actionId = _queueAction();
        ITimelockQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        uint256 timestamp = bound(warpedTimestamp_, action.expiresAt + 1, type(uint48).max);
        vm.warp(timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockQueue.ITimelockQueue_ActionExpired.selector,
                actionId,
                action.expiresAt
            )
        );
        queue.executeQueuedAction(actionId);
    }

    // given _validateExecution rejects
    //  [X] executeQueuedAction reverts without marking the action executed
    // given _executeAction reverts
    //  [X] executeQueuedAction reverts without marking the action executed
    function test_executeQueuedAction_givenValidateExecutionRejects_reverts(
        uint256 warpedTimestamp_
    ) public {
        uint64 actionId = _queueAction();
        _warpReady(actionId, warpedTimestamp_);
        queue.setRejectExecution(true);

        vm.expectRevert(MockTimelockQueue.MockTimelockQueue_ExecutionRejected.selector);
        queue.executeQueuedAction(actionId);

        ITimelockQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        assertEq(action.executed, false, "Executed");
        assertGt(action.payload.length, 0, "Payload retained");
    }

    function test_executeQueuedAction_givenExecuteActionReverts_reverts(
        uint256 warpedTimestamp_
    ) public {
        uint64 actionId = _queueAction();
        _warpReady(actionId, warpedTimestamp_);
        queue.setRevertExecuteAction(true);

        vm.expectRevert(MockTimelockQueue.MockTimelockQueue_ExecuteActionReverted.selector);
        queue.executeQueuedAction(actionId);

        ITimelockQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        assertEq(action.executed, false, "Executed");
        assertGt(action.payload.length, 0, "Payload retained");
    }

    // given an action has been cancelled
    //  [X] executeQueuedAction reverts
    // given an action has been executed
    //  [X] executeQueuedAction reverts
    function test_executeQueuedAction_givenActionCancelled_reverts() public {
        uint64 actionId = _queueAction();
        queue.cancelQueuedAction(actionId);

        vm.warp(queue.getQueuedAction(actionId).executableAt);

        vm.expectRevert(
            abi.encodeWithSelector(ITimelockQueue.ITimelockQueue_ActionCancelled.selector, actionId)
        );
        queue.executeQueuedAction(actionId);
    }

    function test_executeQueuedAction_givenActionAlreadyExecuted_reverts(
        uint256 warpedTimestamp_
    ) public {
        uint64 actionId = _queueAction();
        _warpReady(actionId, warpedTimestamp_);
        queue.executeQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockQueue.ITimelockQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.executeQueuedAction(actionId);
    }

    // given _validateCancellation rejects
    //  [X] cancelQueuedAction reverts without cancelling
    // given _validateCancellation accepts
    //  [X] cancelQueuedAction cancels and clears payload
    function test_cancelQueuedAction_givenValidateCancellationRejects_reverts() public {
        uint64 actionId = _queueAction();
        queue.setRejectCancellation(true);

        vm.expectRevert(MockTimelockQueue.MockTimelockQueue_CancellationRejected.selector);
        queue.cancelQueuedAction(actionId);

        ITimelockQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        assertEq(action.cancelled, false, "Cancelled");
        assertGt(action.payload.length, 0, "Payload retained");
    }

    function test_cancelQueuedAction_succeeds(address canceller_) public {
        uint64 actionId = _queueAction();

        vm.expectEmit(true, true, true, true);
        emit ITimelockQueue.TimelockActionCancelled(actionId, target, selector, canceller_);

        vm.prank(canceller_);
        queue.cancelQueuedAction(actionId);

        ITimelockQueue.QueuedAction memory action = queue.getQueuedAction(actionId);
        assertEq(action.cancelled, true, "Cancelled");
        assertEq(action.payload.length, 0, "Payload cleared");
    }

    function test_cancelQueuedAction_givenActionDoesNotExist_reverts(uint64 actionId_) public {
        vm.assume(actionId_ != 0);

        vm.expectRevert(
            abi.encodeWithSelector(ITimelockQueue.ITimelockQueue_ActionNotFound.selector, actionId_)
        );
        queue.cancelQueuedAction(actionId_);
    }

    function test_cancelQueuedAction_givenActionAlreadyExecuted_reverts(
        uint256 warpedTimestamp_
    ) public {
        uint64 actionId = _queueAction();
        _warpReady(actionId, warpedTimestamp_);
        queue.executeQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockQueue.ITimelockQueue_ActionAlreadyExecuted.selector,
                actionId
            )
        );
        queue.cancelQueuedAction(actionId);
    }

    function test_cancelQueuedAction_givenActionAlreadyCancelled_reverts() public {
        uint64 actionId = _queueAction();
        queue.cancelQueuedAction(actionId);

        vm.expectRevert(
            abi.encodeWithSelector(ITimelockQueue.ITimelockQueue_ActionCancelled.selector, actionId)
        );
        queue.cancelQueuedAction(actionId);
    }
}
