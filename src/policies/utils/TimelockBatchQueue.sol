// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {ERC165} from "@openzeppelin-5.3.0/utils/introspection/ERC165.sol";

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title  TimelockBatchQueue
/// @notice Reusable queue implementation for atomic batched timelocked actions.
/// @dev    Every queued action is a batch of one or more `BatchAction` sub-actions. A batch of
///         length one behaves like a single timelocked action. Batches are atomic by
///         construction: a revert in any sub-action validator or executor rolls back the entire
///         batch.
///
///         Lifecycle:
///         - `_queueAction` enforces the configured batch size bounds, calls
///           `_validateSubAction` per sub-action and `_validateBatch` once for cross-sub
///           invariants, stores the batch metadata and sub-actions, emits
///           `TimelockActionQueued`, and emits one `TimelockSubActionQueued` per sub-action.
///         - `executeQueuedAction` validates standard executable state, delegates
///           implementation-specific execution authorization to `_validateExecution`, marks
///           the action executed, and runs the execution loop in the base contract: each
///           iteration calls `_executeSubAction` and then emits `TimelockSubActionExecuted`,
///           interleaving the per-sub event with any events emitted by the sub-action target.
///           After the loop the stored sub-actions are cleared and a single
///           `TimelockActionExecuted` event is emitted.
///         - `cancelQueuedAction` validates standard cancellable state, delegates
///           implementation-specific cancellation authorization to `_validateCancellation`,
///           clears the stored sub-actions, and emits `TimelockActionCancelled`.
///
///         Child contracts must implement the virtual hooks by reverting on failure. Hooks
///         should not return booleans; a successful return means the hook accepted the
///         operation.
abstract contract TimelockBatchQueue is ITimelockBatchQueue, ERC165 {
    // ========== STATE ========== //

    /// @inheritdoc ITimelockBatchQueue
    uint48 public timelockDelay;

    /// @inheritdoc ITimelockBatchQueue
    uint64 public nextActionId;

    /// @notice Queued timelock actions.
    mapping(uint64 => ITimelockBatchQueue.QueuedAction) internal _queuedActions;

    // ========== CONSTRUCTOR ========== //

    /// @notice Initialize the timelock queue.
    /// @dev    Calls `_validateTimelockDelay`. Child implementations should ensure that override
    ///         does not depend on child constructor-initialized storage.
    ///
    /// @param  initialTimelockDelay_ Initial timelock delay in seconds.
    constructor(uint48 initialTimelockDelay_) {
        _validateTimelockDelay(initialTimelockDelay_);

        timelockDelay = initialTimelockDelay_;
        nextActionId = 1;

        emit TimelockDelaySet(initialTimelockDelay_);
    }

    // ========== QUEUE MANAGEMENT ========== //

    /// @inheritdoc ITimelockBatchQueue
    /// @dev        Reverts if:
    ///             - The action does not exist
    function getQueuedAction(
        uint64 actionId_
    ) external view returns (ITimelockBatchQueue.QueuedAction memory action_) {
        action_ = _queuedActions[actionId_];
        if (action_.queuedAt == 0) revert ITimelockBatchQueue_ActionNotFound(actionId_);
    }

    /// @inheritdoc ITimelockBatchQueue
    /// @dev        Reverts if:
    ///             - The action does not exist
    ///             - The action has already been executed
    ///             - The action has been cancelled
    function getQueuedActionLength(uint64 actionId_) external view returns (uint256 length_) {
        ITimelockBatchQueue.QueuedAction storage action = _queuedActions[actionId_];
        _requireActionAccessible(actionId_, action);
        return action.actions.length;
    }

    /// @inheritdoc ITimelockBatchQueue
    /// @dev        Reverts if:
    ///             - The action does not exist
    ///             - The action has already been executed
    ///             - The action has been cancelled
    ///             - The sub-action index is out of bounds
    function getQueuedSubAction(
        uint64 actionId_,
        uint256 index_
    ) external view returns (address target_, bytes4 selector_, bytes memory payload_) {
        ITimelockBatchQueue.QueuedAction storage action = _queuedActions[actionId_];
        _requireActionAccessible(actionId_, action);

        uint256 length = action.actions.length;
        if (index_ >= length)
            revert ITimelockBatchQueue_SubActionIndexOutOfBounds(actionId_, index_, length);

        ITimelockBatchQueue.BatchAction storage subAction = action.actions[index_];
        target_ = subAction.target;
        selector_ = subAction.selector;
        payload_ = subAction.payload;
    }

    /// @inheritdoc ITimelockBatchQueue
    /// @dev        Reverts if:
    ///             - The action does not exist
    ///             - The action has already been executed
    ///             - The action has been cancelled
    ///             - The action is still timelocked
    ///             - The action has expired
    ///             - `_validateExecution` reverts
    ///             - `_executeSubAction` reverts for any sub-action
    /// @dev        Event ordering is intentionally asymmetric vs `_queueAction`. Each
    ///             `TimelockSubActionExecuted` is emitted *inside* the loop, immediately after
    ///             the corresponding `_executeSubAction` call, so it interleaves with any
    ///             events the sub-action target emits and the log preserves real execution
    ///             order. The single `TimelockActionExecuted` event closes the batch at the
    ///             end. At queue time there is no nested call to interleave with, so
    ///             `_queueAction` emits the action-level event first and the sub-action events
    ///             follow as a uniform group.
    function executeQueuedAction(uint64 actionId_) external {
        ITimelockBatchQueue.QueuedAction storage action = _queuedActions[actionId_];
        _validateExecutableState(actionId_, action);

        ITimelockBatchQueue.QueuedAction memory actionCopy = action;
        _validateExecution(msg.sender, actionId_, actionCopy);

        action.executed = true;

        uint256 len = actionCopy.actions.length;
        for (uint256 i; i < len; ++i) {
            ITimelockBatchQueue.BatchAction memory subAction = actionCopy.actions[i];
            _executeSubAction(actionId_, i, subAction);
            emit TimelockSubActionExecuted(actionId_, subAction.target, subAction.selector, i);
        }

        delete action.actions;

        emit TimelockActionExecuted(actionId_, msg.sender);
    }

    /// @inheritdoc ITimelockBatchQueue
    /// @dev        Reverts if:
    ///             - The action does not exist
    ///             - The action has already been executed
    ///             - The action has been cancelled
    ///             - `_validateCancellation` reverts
    function cancelQueuedAction(uint64 actionId_) external {
        ITimelockBatchQueue.QueuedAction storage action = _queuedActions[actionId_];
        _validateCancellableState(actionId_, action);

        ITimelockBatchQueue.QueuedAction memory actionCopy = action;
        _validateCancellation(msg.sender, actionId_, actionCopy);

        action.cancelled = true;
        delete action.actions;

        emit TimelockActionCancelled(actionId_, msg.sender);
    }

    /// @notice Queue a batched timelocked action.
    /// @dev    Calls `_validateSubAction` per sub-action and `_validateBatch` once after, so
    ///         child contracts cannot use this helper without passing their implementation
    ///         specific authorization and payload checks.
    /// @dev    Reverts if:
    ///         - The batch is empty
    ///         - The batch exceeds `_maxBatchSize()`
    ///         - `_validateSubAction` reverts for any sub-action
    ///         - `_validateBatch` reverts
    ///
    /// @param  actions_  The sub-actions of the batch.
    /// @return actionId_ The queued action ID.
    function _queueAction(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal returns (uint64 actionId_) {
        uint256 len = actions_.length;
        if (len == 0) revert ITimelockBatchQueue_BatchEmpty();
        uint256 maxLen = _maxBatchSize();
        if (len > maxLen) revert ITimelockBatchQueue_BatchTooLarge(len, maxLen);

        for (uint256 i; i < len; ++i) {
            _validateSubAction(msg.sender, actions_[i]);
        }
        _validateBatch(msg.sender, actions_);

        uint48 queuedAt = uint48(block.timestamp);
        uint48 executableAt = queuedAt + timelockDelay;
        uint48 expiresAt = executableAt + _executionWindow();

        actionId_ = nextActionId;
        nextActionId = actionId_ + 1;

        // The legacy pipeline cannot copy a memory array of structs containing nested dynamic
        // types (`BatchAction[] memory` -> storage) in a single assignment, so push one
        // sub-action at a time. `executed` and `cancelled` default to false in the fresh
        // storage slot.
        ITimelockBatchQueue.QueuedAction storage stored = _queuedActions[actionId_];
        stored.proposer = msg.sender;
        stored.queuedAt = queuedAt;
        stored.executableAt = executableAt;
        stored.expiresAt = expiresAt;
        for (uint256 i; i < len; ++i) {
            stored.actions.push(actions_[i]);
        }

        emit TimelockActionQueued(
            actionId_,
            msg.sender,
            keccak256(abi.encode(actions_)),
            executableAt,
            expiresAt
        );

        for (uint256 i; i < len; ++i) {
            emit TimelockSubActionQueued(
                actionId_,
                actions_[i].target,
                actions_[i].selector,
                i,
                keccak256(actions_[i].payload)
            );
        }
    }

    /// @notice Queue a single timelocked action.
    /// @dev    Convenience wrapper that forwards a single (target, selector, payload) triple as
    ///         a length-1 batch and delegates to the batch overload. The child's
    ///         `_validateSubAction` hook is invoked once and `_validateBatch` is invoked once
    ///         with a length-1 array.
    ///
    /// @param  target_   The contract expected to receive the queued action.
    /// @param  selector_ The function selector for the queued action.
    /// @param  payload_  Encoded parameters for the action.
    /// @return actionId_ The queued action ID.
    function _queueAction(
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) internal returns (uint64 actionId_) {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = ITimelockBatchQueue.BatchAction({
            target: target_,
            selector: selector_,
            payload: payload_
        });
        return _queueAction(actions);
    }

    /// @notice Set the timelock delay.
    /// @dev    Reverts if `_validateTimelockDelay` rejects the new delay.
    ///
    /// @param  delay_ The new timelock delay in seconds.
    function _setTimelockDelay(uint48 delay_) internal {
        _validateTimelockDelay(delay_);

        timelockDelay = delay_;

        emit TimelockDelaySet(delay_);
    }

    /// @notice Validate standard executable state for a queued action.
    /// @dev    Reverts on failure.
    ///
    /// @param  actionId_ The queued action ID.
    /// @param  action_   The queued action storage reference.
    function _validateExecutableState(
        uint64 actionId_,
        ITimelockBatchQueue.QueuedAction storage action_
    ) internal view {
        _requireActionAccessible(actionId_, action_);
        if (block.timestamp < action_.executableAt)
            revert ITimelockBatchQueue_ActionNotReady(actionId_, action_.executableAt);
        if (block.timestamp > action_.expiresAt)
            revert ITimelockBatchQueue_ActionExpired(actionId_, action_.expiresAt);
    }

    /// @notice Validate standard cancellable state for a queued action.
    /// @dev    Reverts on failure.
    ///
    /// @param  actionId_ The queued action ID.
    /// @param  action_   The queued action storage reference.
    function _validateCancellableState(
        uint64 actionId_,
        ITimelockBatchQueue.QueuedAction storage action_
    ) internal view {
        _requireActionAccessible(actionId_, action_);
    }

    /// @notice Reverts if the action does not exist, has been executed, or has been cancelled.
    /// @dev    Common precondition for lifecycle validators and for the view functions that
    ///         expose sub-action data. Sub-action arrays are cleared on execute and cancel
    ///         while the corresponding flags remain set, so this helper distinguishes "never
    ///         queued" from "already executed" from "already cancelled" with explicit reverts.
    ///
    /// @param  actionId_ The queued action ID.
    /// @param  action_   The queued action storage reference.
    function _requireActionAccessible(
        uint64 actionId_,
        ITimelockBatchQueue.QueuedAction storage action_
    ) internal view {
        if (action_.queuedAt == 0) revert ITimelockBatchQueue_ActionNotFound(actionId_);
        if (action_.executed) revert ITimelockBatchQueue_ActionAlreadyExecuted(actionId_);
        if (action_.cancelled) revert ITimelockBatchQueue_ActionCancelled(actionId_);
    }

    /// @notice Validate a single sub-action at queue time.
    /// @dev    Child contracts must revert on failure. Called once per sub-action by the base
    ///         contract before the batch is stored; implementations are expected to validate
    ///         the target, selector, and payload of the sub-action in isolation. Cross
    ///         sub-action invariants belong in `_validateBatch`. The caller is passed
    ///         explicitly for clarity and to support child contracts that centralize
    ///         authorization around actor params.
    ///
    /// @param  caller_ The account queueing the action.
    /// @param  action_ The sub-action being queued.
    function _validateSubAction(
        address caller_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view virtual;

    /// @notice Validate cross-sub-action invariants at queue time.
    /// @dev    Default implementation is a no-op. Child contracts override only when invariants
    ///         spanning multiple sub-actions are required (e.g. forbidding duplicate or
    ///         conflicting sub-actions inside one batch). Called once per queued batch after
    ///         every `_validateSubAction` has returned successfully.
    function _validateBatch(
        address /* caller_ */,
        ITimelockBatchQueue.BatchAction[] memory /* actions_ */
    ) internal view virtual {}

    /// @notice Validate implementation-specific execution rules for the entire batch.
    /// @dev    Child contracts must revert on failure. Standard queued-action state and
    ///         timestamp checks have already passed when this hook is called, and no
    ///         sub-action has been executed yet. This hook is the right place for batch-level
    ///         execution gates (e.g. requiring an execution role, checking that the policy is
    ///         enabled). Per-sub-action execution behavior belongs in `_executeSubAction`.
    ///
    /// @param  caller_   The account executing the action.
    /// @param  actionId_ The queued action ID.
    /// @param  action_   A memory copy of the queued action, including the sub-actions.
    function _validateExecution(
        address caller_,
        uint64 actionId_,
        ITimelockBatchQueue.QueuedAction memory action_
    ) internal view virtual;

    /// @notice Validate implementation-specific cancellation rules.
    /// @dev    Child contracts must revert on failure. Standard queued-action state checks have
    ///         already passed when this hook is called.
    ///
    /// @param  caller_   The account cancelling the action.
    /// @param  actionId_ The queued action ID.
    /// @param  action_   A memory copy of the queued action, including the sub-actions.
    function _validateCancellation(
        address caller_,
        uint64 actionId_,
        ITimelockBatchQueue.QueuedAction memory action_
    ) internal view virtual;

    /// @notice Execute a single sub-action of a batched queued action.
    /// @dev    Child contracts must revert on failure. Called by the base contract once per
    ///         sub-action in array order; the action has already been marked executed, so a
    ///         revert in any iteration reverts the entire batch and rolls back that flag.
    ///         Child contracts must not rely on the base contract calling this hook in any
    ///         other order.
    ///
    /// @param  actionId_ The queued action ID.
    /// @param  index_    The position of the sub-action within the batch.
    /// @param  action_   The sub-action to execute.
    function _executeSubAction(
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal virtual;

    /// @notice Validate a timelock delay.
    /// @dev    Child contracts must revert on failure.
    ///
    /// @param  delay_ The delay to validate.
    function _validateTimelockDelay(uint48 delay_) internal view virtual;

    /// @notice Return the execution window for queued actions.
    ///
    /// @return executionWindow_ The execution window in seconds.
    function _executionWindow() internal view virtual returns (uint48 executionWindow_);

    /// @notice Maximum number of sub-actions allowed in a single batch.
    /// @dev    Default protects against batches that cannot be executed within the block gas
    ///         limit. Child contracts whose sub-actions are unusually expensive or cheap may
    ///         override.
    ///
    /// @return maxBatchSize_ The maximum number of sub-actions allowed in a single batch.
    function _maxBatchSize() internal view virtual returns (uint256 maxBatchSize_) {
        return 15;
    }

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface.
    /// @dev    Does not revert.
    ///
    /// @param  interfaceId_ The interface identifier, as specified in ERC-165.
    /// @return bool         True if the contract implements `interfaceId_`.
    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(ITimelockBatchQueue).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
