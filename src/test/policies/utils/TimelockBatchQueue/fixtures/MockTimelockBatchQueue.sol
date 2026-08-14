// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

contract MockTimelockBatchQueue is TimelockBatchQueue {
    error MockTimelockBatchQueue_SubActionRejected();
    error MockTimelockBatchQueue_SubActionRejectedAt(uint256 index);
    error MockTimelockBatchQueue_BatchRejected();
    error MockTimelockBatchQueue_ExecutionRejected();
    error MockTimelockBatchQueue_CancellationRejected();
    error MockTimelockBatchQueue_CancellationHookReverted();
    error MockTimelockBatchQueue_ExecutionReverted(uint256 value);
    error MockTimelockBatchQueue_CompletionReverted();

    struct ExecuteSubActionCall {
        uint64 actionId;
        uint256 index;
        address target;
        bytes4 selector;
        bytes32 payloadHash;
    }

    struct CompletionCall {
        uint64 actionId;
        uint256 subActionCount;
        uint256 executionCount;
    }

    struct CancellationCall {
        uint64 actionId;
        uint256 subActionCount;
    }

    uint48 public constant MIN_DELAY = 1 days;
    uint48 public constant MAX_DELAY = 30 days;
    uint256 private constant _NO_REJECT_INDEX = type(uint256).max;

    uint48 public executionWindow = 7 days;
    uint256 public maxBatchSizeOverride;
    uint256 public rejectSubActionAtIndex = _NO_REJECT_INDEX;
    uint256 public revertExecutionValue = type(uint256).max;

    address public queueCaller;
    address public executionCaller;
    address public cancellationCaller;
    address public callThroughTarget;

    bool public rejectSubAction;
    bool public rejectBatch;
    bool public rejectExecution;
    bool public rejectCancellation;
    bool public rejectCancellationHook;
    bool public rejectCompletion;

    uint256[] private _executedValues;
    ExecuteSubActionCall[] private _executeSubActionCalls;
    CompletionCall[] private _completionCalls;
    CancellationCall[] private _cancellationCalls;

    constructor(uint48 initialTimelockDelay_) TimelockBatchQueue(initialTimelockDelay_) {}

    function queueAction(
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) external returns (uint64 actionId) {
        return _queueAction(target_, selector_, payload_);
    }

    function queueBatchAction(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId) {
        return _queueAction(actions_);
    }

    function setTimelockDelay(uint48 delay_) external {
        _setTimelockDelay(delay_);
    }

    function setExecutionWindow(uint48 executionWindow_) external {
        executionWindow = executionWindow_;
    }

    function setMaxBatchSizeOverride(uint256 maximum_) external {
        maxBatchSizeOverride = maximum_;
    }

    function setRejectSubActionAtIndex(uint256 index_) external {
        rejectSubActionAtIndex = index_;
    }

    function setRevertExecutionValue(uint256 value_) external {
        revertExecutionValue = value_;
    }

    function setQueueCaller(address caller_) external {
        queueCaller = caller_;
    }

    function setExecutionCaller(address caller_) external {
        executionCaller = caller_;
    }

    function setCancellationCaller(address caller_) external {
        cancellationCaller = caller_;
    }

    function setCallThroughTarget(address target_) external {
        callThroughTarget = target_;
    }

    function setRejectSubAction(bool reject_) external {
        rejectSubAction = reject_;
    }

    function setRejectBatch(bool reject_) external {
        rejectBatch = reject_;
    }

    function setRejectExecution(bool reject_) external {
        rejectExecution = reject_;
    }

    function setRejectCancellation(bool reject_) external {
        rejectCancellation = reject_;
    }

    function setRejectCancellationHook(bool reject_) external {
        rejectCancellationHook = reject_;
    }

    function setRejectCompletion(bool reject_) external {
        rejectCompletion = reject_;
    }

    function getExecutedValues() external view returns (uint256[] memory values) {
        return _executedValues;
    }

    function getExecuteSubActionCalls()
        external
        view
        returns (ExecuteSubActionCall[] memory calls)
    {
        return _executeSubActionCalls;
    }

    function getCompletionCalls() external view returns (CompletionCall[] memory calls) {
        return _completionCalls;
    }

    function getCancellationCalls() external view returns (CancellationCall[] memory calls) {
        return _cancellationCalls;
    }

    function getMaxBatchSize() external view returns (uint256 maximum) {
        return _maxBatchSize();
    }

    function _onSubActionQueued(
        address caller_,
        uint64,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory
    ) internal view override {
        if (rejectSubAction) revert MockTimelockBatchQueue_SubActionRejected();
        if (queueCaller != address(0) && caller_ != queueCaller) {
            revert MockTimelockBatchQueue_SubActionRejected();
        }
        if (index_ == rejectSubActionAtIndex) {
            revert MockTimelockBatchQueue_SubActionRejectedAt(index_);
        }
    }

    function _onBatchQueued(
        address,
        uint64,
        ITimelockBatchQueue.BatchAction[] memory
    ) internal view override {
        if (rejectBatch) revert MockTimelockBatchQueue_BatchRejected();
    }

    function _validateExecution(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        if (rejectExecution || (executionCaller != address(0) && caller_ != executionCaller)) {
            revert MockTimelockBatchQueue_ExecutionRejected();
        }
    }

    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        if (
            rejectCancellation ||
            (cancellationCaller != address(0) && caller_ != cancellationCaller)
        ) {
            revert MockTimelockBatchQueue_CancellationRejected();
        }
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
            (bool success, bytes memory returnData) = action_.target.call(action_.payload);
            if (!success) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
            return;
        }

        uint256 value = abi.decode(action_.payload, (uint256));
        if (value == revertExecutionValue) {
            revert MockTimelockBatchQueue_ExecutionReverted(value);
        }
        _executedValues.push(value);
    }

    function _onActionExecuted(uint64 actionId_, uint256 subActionCount_) internal override {
        if (rejectCompletion) revert MockTimelockBatchQueue_CompletionReverted();
        _completionCalls.push(
            CompletionCall({
                actionId: actionId_,
                subActionCount: subActionCount_,
                executionCount: _executedValues.length
            })
        );
    }

    function _onActionCancelled(uint64 actionId_, uint256 subActionCount_) internal override {
        if (rejectCancellationHook) revert MockTimelockBatchQueue_CancellationHookReverted();
        _cancellationCalls.push(
            CancellationCall({actionId: actionId_, subActionCount: subActionCount_})
        );
    }

    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ < MIN_DELAY || delay_ > MAX_DELAY) {
            revert ITimelockBatchQueue_TimelockDelayInvalid(delay_, MIN_DELAY, MAX_DELAY);
        }
    }

    function _executionWindow() internal view override returns (uint48) {
        return executionWindow;
    }

    function _maxBatchSize() internal view override returns (uint256) {
        return maxBatchSizeOverride == 0 ? super._maxBatchSize() : maxBatchSizeOverride;
    }
}
