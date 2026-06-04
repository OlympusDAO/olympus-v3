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
///         Sub-actions execute in array order within a batch, but no ordering is enforced
///         across separately queued actions: execution is permissionless once a timelock
///         elapses, so independently queued batches may execute in any order. Actions with
///         execution-order dependencies must be queued within a single batch.
///
///         Lifecycle:
///         - `_queueAction` enforces the configured batch size bounds, calls
///           `_onSubActionQueued` per sub-action and `_onBatchQueued` once for cross-sub
///           invariants, stores the batch metadata and sub-actions, emits one
///           `TimelockSubActionQueued` per sub-action, then emits `TimelockActionQueued`
///           to close the batch.
///         - `executeQueuedAction` validates standard executable state, delegates
///           implementation-specific execution authorization to `_validateExecution`, marks
///           the action executed, and runs the execution loop in the base contract: each
///           iteration calls `_executeSubAction` and then emits `TimelockSubActionExecuted`,
///           interleaving the per-sub event with any events emitted by the sub-action target.
///           After the loop the stored sub-actions are cleared and a single
///           `TimelockActionExecuted` event is emitted.
///         - `cancelQueuedAction` validates standard cancellable state, delegates
///           implementation-specific cancellation authorization to `_validateCancellation`,
///           clears the stored sub-actions, calls `_onActionCancelled` so derived contracts
///           can clear per-sub-action state recorded at queue time, and emits
///           `TimelockActionCancelled`.
///
///         Derived contracts must implement the virtual hooks by reverting on failure. Hooks
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
    /// @dev    Delegates to `_setTimelockDelay`, which calls the virtual
    ///         `_validateTimelockDelay`. Derived implementations should ensure that override does
    ///         not depend on derived-contract constructor-initialized storage.
    ///
    /// @param  initialTimelockDelay_ Initial timelock delay in seconds.
    constructor(uint48 initialTimelockDelay_) {
        _setTimelockDelay(initialTimelockDelay_);

        nextActionId = 1;
    }

    // ========== QUEUE MANAGEMENT ========== //

    /// @inheritdoc ITimelockBatchQueue
    /// @dev        Reverts if:
    ///             - The action does not exist
    function getQueuedAction(
        uint64 actionId_
    ) external view returns (ITimelockBatchQueue.QueuedAction memory action) {
        action = _queuedActions[actionId_];
        if (action.queuedAt == 0) revert ITimelockBatchQueue_ActionNotFound(actionId_);
    }

    /// @inheritdoc ITimelockBatchQueue
    /// @dev        Reverts if:
    ///             - The action does not exist
    ///             - The action has already been executed
    ///             - The action has been cancelled
    function getQueuedActionLength(uint64 actionId_) external view returns (uint256 length) {
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
    ) external view returns (address target, bytes4 selector, bytes memory payload) {
        ITimelockBatchQueue.QueuedAction storage action = _queuedActions[actionId_];
        _requireActionAccessible(actionId_, action);

        uint256 length = action.actions.length;
        if (index_ >= length)
            revert ITimelockBatchQueue_SubActionIndexOutOfBounds(actionId_, index_, length);

        ITimelockBatchQueue.BatchAction storage subAction = action.actions[index_];
        target = subAction.target;
        selector = subAction.selector;
        payload = subAction.payload;
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
    ///
    ///             In both `_queueAction` and execution the per-sub-action events precede the
    ///             single action-level event that closes the batch. At execution time each
    ///             `TimelockSubActionExecuted` is emitted *inside* the loop, immediately after
    ///             the corresponding `_executeSubAction` call, so it interleaves with any
    ///             events the sub-action target emits and the log preserves real execution
    ///             order; `TimelockActionExecuted` is then emitted once after the loop. At
    ///             queue time there is no nested call to interleave with, so the
    ///             `TimelockSubActionQueued` events form a uniform group followed by
    ///             `TimelockActionQueued`.
    function executeQueuedAction(uint64 actionId_) external {
        ITimelockBatchQueue.QueuedAction storage action = _queuedActions[actionId_];
        _validateExecutableState(actionId_, action);

        _validateExecution(msg.sender, actionId_, action);

        action.executed = true;

        uint256 len = action.actions.length;
        for (uint256 i = 0; i < len; ++i) {
            ITimelockBatchQueue.BatchAction memory subAction = action.actions[i];
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
    ///             - `_onActionCancelled` reverts
    function cancelQueuedAction(uint64 actionId_) external {
        ITimelockBatchQueue.QueuedAction storage action = _queuedActions[actionId_];
        _validateCancellableState(actionId_, action);

        _validateCancellation(msg.sender, actionId_, action);

        action.cancelled = true;

        uint256 len = action.actions.length;
        delete action.actions;

        _onActionCancelled(actionId_, len);

        emit TimelockActionCancelled(actionId_, msg.sender);
    }

    /// @notice Queue a batched timelocked action.
    /// @dev    Calls `_onSubActionQueued` per sub-action and `_onBatchQueued` once after, so
    ///         derived contracts cannot use this helper without passing their implementation
    ///         specific authorization and payload checks.
    ///
    ///         Reverts if:
    ///         - The batch is empty
    ///         - The batch exceeds `_maxBatchSize()`
    ///         - `_onSubActionQueued` reverts for any sub-action
    ///         - `_onBatchQueued` reverts
    ///
    /// @param  actions_  The sub-actions of the batch.
    /// @return actionId The queued action ID.
    function _queueAction(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal returns (uint64 actionId) {
        uint256 len = actions_.length;
        if (len == 0) revert ITimelockBatchQueue_BatchEmpty();
        if (len > _maxBatchSize()) revert ITimelockBatchQueue_BatchTooLarge(len, _maxBatchSize());

        actionId = nextActionId;
        nextActionId = actionId + 1;

        for (uint256 i = 0; i < len; ++i) {
            _onSubActionQueued(msg.sender, actionId, i, actions_[i]);
        }
        _onBatchQueued(msg.sender, actionId, actions_);

        uint48 queuedAt = uint48(block.timestamp);
        uint48 executableAt = queuedAt + timelockDelay;
        uint48 expiresAt = executableAt + _executionWindow();

        // The legacy pipeline cannot copy a memory array of structs containing nested dynamic
        // types (`BatchAction[] memory` -> storage) in a single assignment, so push one
        // sub-action at a time. `executed` and `cancelled` default to false in the fresh
        // storage slot.
        ITimelockBatchQueue.QueuedAction storage stored = _queuedActions[actionId];
        stored.proposer = msg.sender;
        stored.queuedAt = queuedAt;
        stored.executableAt = executableAt;
        stored.expiresAt = expiresAt;
        for (uint256 i = 0; i < len; ++i) {
            stored.actions.push(actions_[i]);
            emit TimelockSubActionQueued(
                actionId,
                actions_[i].target,
                actions_[i].selector,
                i,
                keccak256(actions_[i].payload)
            );
        }

        emit TimelockActionQueued(
            actionId,
            msg.sender,
            keccak256(abi.encode(actions_)),
            executableAt,
            expiresAt
        );
    }

    /// @notice Queue a single timelocked action.
    /// @dev    Convenience wrapper that forwards a single (target, selector, payload) triple as
    ///         a length-1 batch and delegates to the batch overload. The derived contract's
    ///         `_onSubActionQueued` hook is invoked once and `_onBatchQueued` is invoked once
    ///         with a length-1 array.
    ///
    /// @param  target_   The contract expected to receive the queued action.
    /// @param  selector_ The function selector for the queued action.
    /// @param  payload_  Encoded parameters for the action.
    /// @return actionId The queued action ID.
    function _queueAction(
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) internal returns (uint64 actionId) {
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

    /// @notice Hook invoked once per sub-action at queue time, before the batch is stored.
    /// @dev    Derived contracts must revert on failure. Implementations are expected to
    ///         validate the target, selector, and payload of the sub-action in isolation, and
    ///         may record per-sub-action state. Cross sub-action invariants belong in
    ///         `_onBatchQueued`. The caller is passed explicitly for clarity and to support
    ///         derived contracts that centralize authorization around actor params.
    ///
    /// @param  caller_   The account queueing the action.
    /// @param  actionId_ The id the batch will be stored under.
    /// @param  index_    The position of the sub-action within the batch.
    /// @param  action_   The sub-action being queued.
    function _onSubActionQueued(
        address caller_,
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal virtual;

    /// @notice Hook invoked once per batch at queue time, after every `_onSubActionQueued`.
    /// @dev    Default implementation is a no-op. Derived contracts override only when
    ///         invariants spanning multiple sub-actions are required (e.g. forbidding
    ///         duplicate or conflicting sub-actions inside one batch).
    function _onBatchQueued(
        address /* caller_ */,
        uint64 /* actionId_ */,
        ITimelockBatchQueue.BatchAction[] memory /* actions_ */
    ) internal virtual {}

    /// @notice Validate implementation-specific execution rules for the entire batch.
    /// @dev    Derived contracts must revert on failure. Standard queued-action state and
    ///         timestamp checks have already passed when this hook is called, and no
    ///         sub-action has been executed yet. This hook is the right place for batch-level
    ///         execution gates (e.g. requiring an execution role, checking that the policy is
    ///         enabled). Per-sub-action execution behavior belongs in `_executeSubAction`.
    ///
    /// @param  caller_   The account executing the action.
    /// @param  actionId_ The queued action ID.
    /// @param  action_   The queued action storage reference, including the sub-actions.
    function _validateExecution(
        address caller_,
        uint64 actionId_,
        ITimelockBatchQueue.QueuedAction storage action_
    ) internal view virtual;

    /// @notice Validate implementation-specific cancellation rules.
    /// @dev    Derived contracts must revert on failure. Standard queued-action state checks have
    ///         already passed when this hook is called.
    ///
    /// @param  caller_   The account cancelling the action.
    /// @param  actionId_ The queued action ID.
    /// @param  action_   The queued action storage reference, including the sub-actions.
    function _validateCancellation(
        address caller_,
        uint64 actionId_,
        ITimelockBatchQueue.QueuedAction storage action_
    ) internal view virtual;

    /// @notice Hook invoked once when a queued action is cancelled, after the stored
    ///         sub-actions have been cleared.
    /// @dev    Default implementation is a no-op. Derived contracts override to clear any
    ///         per-sub-action state recorded at queue time by `_onSubActionQueued`. The
    ///         sub-action count is captured before the stored array is deleted, so
    ///         implementations can iterate the indices that were recorded.
    ///
    /// @param  actionId_       The cancelled action ID.
    /// @param  subActionCount_ The number of sub-actions the action held before clearing.
    function _onActionCancelled(uint64 actionId_, uint256 subActionCount_) internal virtual {}

    /// @notice Execute a single sub-action of a batched queued action.
    /// @dev    Derived contracts must revert on failure. Called by the base contract once per
    ///         sub-action in array order; the action has already been marked executed, so a
    ///         revert in any iteration reverts the entire batch and rolls back that flag.
    ///         Derived contracts must not rely on the base contract calling this hook in any
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
    /// @dev    Derived contracts must revert on failure.
    ///
    /// @param  delay_ The delay to validate.
    function _validateTimelockDelay(uint48 delay_) internal view virtual;

    /// @notice Return the execution window for queued actions.
    ///
    /// @return executionWindow The execution window in seconds.
    function _executionWindow() internal view virtual returns (uint48 executionWindow);

    /// @notice Maximum number of sub-actions allowed in a single batch.
    /// @dev    Default protects against batches that cannot be executed within the block gas
    ///         limit. Derived contracts whose sub-actions are unusually expensive or cheap may
    ///         override.
    ///
    /// @return maxBatchSize The maximum number of sub-actions allowed in a single batch.
    function _maxBatchSize() internal view virtual returns (uint256 maxBatchSize) {
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
