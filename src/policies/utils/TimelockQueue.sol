// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";

import {ITimelockQueue} from "src/policies/interfaces/utils/ITimelockQueue.sol";

/// @title  TimelockQueue
/// @notice Reusable queue implementation for timelocked actions.
/// @dev    This contract owns the standard queue lifecycle:
///         - `_queueAction` validates queue authorization via `_validateQueue`, stores action
///           metadata, and emits `TimelockActionQueued`.
///         - `executeQueuedAction` validates standard executable state, delegates
///           implementation-specific execution authorization to `_validateExecution`, runs
///           `_executeAction`, clears the payload, and emits `TimelockActionExecuted`.
///         - `cancelQueuedAction` validates standard cancellable state, delegates
///           implementation-specific cancellation authorization to `_validateCancellation`,
///           clears the payload, and emits `TimelockActionCancelled`.
///
///         Child contracts must implement the virtual hooks by reverting on failure. Hooks should
///         not return booleans; a successful return means the hook accepted the operation.
abstract contract TimelockQueue is ITimelockQueue {
    // ========== STATE ========== //

    /// @inheritdoc ITimelockQueue
    uint48 public timelockDelay;

    /// @inheritdoc ITimelockQueue
    uint64 public nextActionId;

    /// @notice Queued timelock actions.
    mapping(uint64 => ITimelockQueue.QueuedAction) internal _queuedActions;

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

    /// @inheritdoc ITimelockQueue
    /// @dev        Reverts if:
    ///             - The action does not exist
    function getQueuedAction(
        uint64 actionId_
    ) external view returns (ITimelockQueue.QueuedAction memory action_) {
        action_ = _queuedActions[actionId_];
        if (action_.queuedAt == 0) revert ITimelockQueue_ActionNotFound(actionId_);
    }

    /// @inheritdoc ITimelockQueue
    /// @dev        Reverts if:
    ///             - The action does not exist
    ///             - The action has already been executed
    ///             - The action has been cancelled
    ///             - The action is still timelocked
    ///             - The action has expired
    ///             - `_validateExecution` reverts
    ///             - `_executeAction` reverts
    function executeQueuedAction(uint64 actionId_) external {
        ITimelockQueue.QueuedAction storage action = _queuedActions[actionId_];
        _validateExecutableState(actionId_, action);

        ITimelockQueue.QueuedAction memory actionCopy = action;
        _validateExecution(msg.sender, actionId_, actionCopy);

        action.executed = true;

        _executeAction(actionId_, actionCopy);

        delete action.payload;

        emit TimelockActionExecuted(actionId_, actionCopy.target, actionCopy.selector, msg.sender);
    }

    /// @inheritdoc ITimelockQueue
    /// @dev        Reverts if:
    ///             - The action does not exist
    ///             - The action has already been executed
    ///             - The action has been cancelled
    ///             - `_validateCancellation` reverts
    function cancelQueuedAction(uint64 actionId_) external {
        ITimelockQueue.QueuedAction storage action = _queuedActions[actionId_];
        _validateCancellableState(actionId_, action);

        ITimelockQueue.QueuedAction memory actionCopy = action;
        _validateCancellation(msg.sender, actionId_, actionCopy);

        action.cancelled = true;
        delete action.payload;

        emit TimelockActionCancelled(actionId_, actionCopy.target, actionCopy.selector, msg.sender);
    }

    /// @notice Queue a timelocked action.
    /// @dev    Calls `_validateQueue` internally so child contracts cannot use this helper without
    ///         passing their implementation-specific queue authorization and payload checks.
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
        _validateQueue(msg.sender, target_, selector_, payload_);

        uint48 queuedAt = uint48(block.timestamp);
        uint48 executableAt = queuedAt + timelockDelay;
        uint48 expiresAt = executableAt + _executionWindow();

        actionId_ = nextActionId;
        nextActionId = actionId_ + 1;

        _queuedActions[actionId_] = ITimelockQueue.QueuedAction({
            target: target_,
            selector: selector_,
            proposer: msg.sender,
            queuedAt: queuedAt,
            executableAt: executableAt,
            expiresAt: expiresAt,
            executed: false,
            cancelled: false,
            payload: payload_
        });

        emit TimelockActionQueued(
            actionId_,
            target_,
            selector_,
            msg.sender,
            keccak256(payload_),
            executableAt,
            expiresAt
        );
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
        ITimelockQueue.QueuedAction storage action_
    ) internal view {
        if (action_.queuedAt == 0) revert ITimelockQueue_ActionNotFound(actionId_);
        if (action_.executed) revert ITimelockQueue_ActionAlreadyExecuted(actionId_);
        if (action_.cancelled) revert ITimelockQueue_ActionCancelled(actionId_);
        if (block.timestamp < action_.executableAt)
            revert ITimelockQueue_ActionNotReady(actionId_, action_.executableAt);
        if (block.timestamp > action_.expiresAt)
            revert ITimelockQueue_ActionExpired(actionId_, action_.expiresAt);
    }

    /// @notice Validate standard cancellable state for a queued action.
    /// @dev    Reverts on failure.
    ///
    /// @param  actionId_ The queued action ID.
    /// @param  action_   The queued action storage reference.
    function _validateCancellableState(
        uint64 actionId_,
        ITimelockQueue.QueuedAction storage action_
    ) internal view {
        if (action_.queuedAt == 0) revert ITimelockQueue_ActionNotFound(actionId_);
        if (action_.executed) revert ITimelockQueue_ActionAlreadyExecuted(actionId_);
        if (action_.cancelled) revert ITimelockQueue_ActionCancelled(actionId_);
    }

    /// @notice Validate whether an action can be queued.
    /// @dev    Child contracts must revert on failure. The caller is passed explicitly for clarity
    ///         and to support child contracts that centralize authorization around actor params.
    ///
    /// @param  caller_   The account queueing the action.
    /// @param  target_   The contract expected to receive the queued action.
    /// @param  selector_ The function selector for the queued action.
    /// @param  payload_  Encoded parameters for the action.
    function _validateQueue(
        address caller_,
        address target_,
        bytes4 selector_,
        bytes memory payload_
    ) internal view virtual;

    /// @notice Validate implementation-specific execution rules.
    /// @dev    Child contracts must revert on failure. Standard queued-action state and timestamp
    ///         checks have already passed when this hook is called.
    ///
    /// @param  caller_   The account executing the action.
    /// @param  actionId_ The queued action ID.
    /// @param  action_   A memory copy of the queued action.
    function _validateExecution(
        address caller_,
        uint64 actionId_,
        ITimelockQueue.QueuedAction memory action_
    ) internal view virtual;

    /// @notice Validate implementation-specific cancellation rules.
    /// @dev    Child contracts must revert on failure. Standard queued-action state checks have
    ///         already passed when this hook is called.
    ///
    /// @param  caller_   The account cancelling the action.
    /// @param  actionId_ The queued action ID.
    /// @param  action_   A memory copy of the queued action.
    function _validateCancellation(
        address caller_,
        uint64 actionId_,
        ITimelockQueue.QueuedAction memory action_
    ) internal view virtual;

    /// @notice Execute an implementation-specific queued action.
    /// @dev    Child contracts must revert on failure. The queued action has already been marked
    ///         executed before this hook is called; a revert rolls back that state change.
    ///
    /// @param  actionId_ The queued action ID.
    /// @param  action_   A memory copy of the queued action.
    function _executeAction(
        uint64 actionId_,
        ITimelockQueue.QueuedAction memory action_
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

    // ========== ERC165 ========== //

    /// @notice Query if a contract implements an interface.
    /// @dev    Does not revert.
    ///
    /// @param  interfaceId_ The interface identifier, as specified in ERC-165.
    /// @return bool         True if the contract implements `interfaceId_`.
    function supportsInterface(bytes4 interfaceId_) public view virtual returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(ITimelockQueue).interfaceId;
    }
}
