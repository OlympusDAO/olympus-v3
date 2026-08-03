// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title  ITimelockBatchQueue
/// @notice Interface for contracts that queue, execute, and cancel atomic batched timelocked
///         actions.
/// @dev    Each queued action represents a batch of one or more `BatchAction` sub-actions. A
///         batch of length one is the single-action case. Implementations are expected to
///         enforce action-specific authorization and execution checks in the concrete contract.
///         Standard queued-action state checks, timestamp checks, and terminal sub-action
///         clearing are handled by the abstract implementation.
///
///         Atomicity is a property of the batch lifecycle: a revert in any sub-action validator
///         or executor reverts the entire batch.
///
///         Ordering is a property of a single batch only: sub-actions execute in array order
///         within their batch, but no ordering is enforced across separately queued actions,
///         so independently queued batches may execute in any order once their timelocks
///         elapse. Actions with execution-order dependencies must be queued within a single
///         batch; independent batches must not be assumed to execute in queue order.
interface ITimelockBatchQueue {
    // ========== EVENTS ========== //

    /// @notice Emitted when a batched action is queued.
    /// @dev    Emitted once to close the batch, after one `TimelockSubActionQueued` event has
    ///         been emitted per sub-action.
    ///
    /// @param actionId     The queued action ID.
    /// @param proposer     The account that queued the action.
    /// @param batchHash    Hash of the encoded batch of sub-actions.
    /// @param executableAt Timestamp at which the action can first be executed.
    /// @param expiresAt    Timestamp after which the action can no longer be executed.
    event TimelockActionQueued(
        uint64 indexed actionId,
        address indexed proposer,
        bytes32 batchHash,
        uint48 executableAt,
        uint48 expiresAt
    );

    /// @notice Emitted once per sub-action when a batched action is queued.
    /// @dev    `target` and `selector` are indexed so off-chain consumers can filter by either
    ///         without decoding the batch.
    ///
    /// @param actionId    The queued action ID.
    /// @param target      The contract expected to receive the sub-action.
    /// @param selector    The function selector for the sub-action.
    /// @param index       The position of the sub-action within the batch.
    /// @param payloadHash Hash of the encoded sub-action payload.
    event TimelockSubActionQueued(
        uint64 indexed actionId,
        address indexed target,
        bytes4 indexed selector,
        uint256 index,
        bytes32 payloadHash
    );

    /// @notice Emitted when a batched action is executed.
    /// @dev    Emitted once at the end of execution, after every `TimelockSubActionExecuted`
    ///         event for the same action.
    ///
    /// @param actionId The queued action ID.
    /// @param executor The account that executed the action.
    event TimelockActionExecuted(uint64 indexed actionId, address indexed executor);

    /// @notice Emitted once per sub-action immediately after that sub-action runs.
    /// @dev    Emitted inside the execution loop after the corresponding sub-action handler
    ///         returns, so it is interleaved with any events emitted by the sub-action target.
    ///         `target` and `selector` are indexed so off-chain consumers can filter by either
    ///         without decoding the batch.
    ///
    /// @param actionId The queued action ID.
    /// @param target   The contract that received the sub-action.
    /// @param selector The function selector for the sub-action.
    /// @param index    The position of the sub-action within the batch.
    event TimelockSubActionExecuted(
        uint64 indexed actionId,
        address indexed target,
        bytes4 indexed selector,
        uint256 index
    );

    /// @notice Emitted when a queued batched action is cancelled.
    ///
    /// @param actionId  The queued action ID.
    /// @param canceller The account that cancelled the action.
    event TimelockActionCancelled(uint64 indexed actionId, address indexed canceller);

    /// @notice Emitted when the timelock delay is changed.
    ///
    /// @param delay The new timelock delay in seconds.
    event TimelockDelaySet(uint48 delay);

    // ========== ERRORS ========== //

    /// @notice Thrown when a queued action does not exist.
    ///
    /// @param actionId The queued action ID.
    error ITimelockBatchQueue_ActionNotFound(uint64 actionId);

    /// @notice Thrown when a queued action has already been executed.
    ///
    /// @param actionId The queued action ID.
    error ITimelockBatchQueue_ActionAlreadyExecuted(uint64 actionId);

    /// @notice Thrown when a queued action has been cancelled.
    ///
    /// @param actionId The queued action ID.
    error ITimelockBatchQueue_ActionCancelled(uint64 actionId);

    /// @notice Thrown when a queued action is executed before its timelock has elapsed.
    ///
    /// @param actionId     The queued action ID.
    /// @param executableAt Timestamp at which the action can first be executed.
    error ITimelockBatchQueue_ActionNotReady(uint64 actionId, uint48 executableAt);

    /// @notice Thrown when a queued action is executed after its execution window.
    ///
    /// @param actionId  The queued action ID.
    /// @param expiresAt Timestamp after which the action can no longer be executed.
    error ITimelockBatchQueue_ActionExpired(uint64 actionId, uint48 expiresAt);

    /// @notice Thrown when a queued sub-action has an unsupported target or selector.
    ///
    /// @param target   The queued target address.
    /// @param selector The queued function selector.
    error ITimelockBatchQueue_ActionInvalid(address target, bytes4 selector);

    /// @notice Thrown when a proposed timelock delay is outside the accepted range.
    ///
    /// @param delay   The proposed delay.
    /// @param minimum The minimum accepted delay.
    /// @param maximum The maximum accepted delay.
    error ITimelockBatchQueue_TimelockDelayInvalid(uint48 delay, uint48 minimum, uint48 maximum);

    /// @notice Thrown when an empty batch is queued.
    error ITimelockBatchQueue_BatchEmpty();

    /// @notice Thrown when a queued batch exceeds the maximum allowed size.
    ///
    /// @param length  The length of the queued batch.
    /// @param maximum The maximum batch size.
    error ITimelockBatchQueue_BatchTooLarge(uint256 length, uint256 maximum);

    /// @notice Thrown when a queried sub-action index is out of bounds for the action.
    ///
    /// @param actionId The queued action ID.
    /// @param index    The requested sub-action index.
    /// @param length   The number of sub-actions stored for the action.
    error ITimelockBatchQueue_SubActionIndexOutOfBounds(
        uint64 actionId,
        uint256 index,
        uint256 length
    );

    // ========== DATA STRUCTURES ========== //

    /// @notice A single sub-action within a batched queued action.
    ///
    /// @param target   The contract expected to receive the sub-action.
    /// @param selector The function selector for the sub-action.
    /// @param payload  Encoded parameters for the sub-action.
    struct BatchAction {
        address target;
        bytes4 selector;
        bytes payload;
    }

    /// @notice Queued timelock action.
    /// @dev    A queued action is always a batch of one or more `BatchAction` sub-actions.
    ///         Length-1 batches represent single actions. Sub-actions are executed in array
    ///         order. After an action has been executed or cancelled the `actions` array is
    ///         emptied; metadata fields (proposer, timestamps, executed, cancelled) remain
    ///         readable for audit purposes.
    ///
    /// @param proposer     The account that queued the action.
    /// @param queuedAt     Timestamp at which the action was queued.
    /// @param executableAt Timestamp at which the action can first be executed.
    /// @param expiresAt    Timestamp after which the action can no longer be executed.
    /// @param executed     Whether the action has been executed.
    /// @param cancelled    Whether the action has been cancelled.
    /// @param actions      The sub-actions of the batch.
    struct QueuedAction {
        address proposer;
        uint48 queuedAt;
        uint48 executableAt;
        uint48 expiresAt;
        bool executed;
        bool cancelled;
        BatchAction[] actions;
    }

    // ========== QUEUE STATE ========== //

    /// @notice Current timelock delay in seconds.
    function timelockDelay() external view returns (uint48);

    /// @notice Next queued action ID.
    function nextActionId() external view returns (uint64);

    /// @notice Get a queued action.
    /// @dev    Returns the historical record of the action for audit purposes. After the action
    ///         has been executed or cancelled the `actions` array is empty; the metadata fields
    ///         (proposer, timestamps, executed, cancelled) are still populated.
    /// @dev    Reverts if the action does not exist.
    ///
    /// @param  actionId_ The queued action ID.
    /// @return action   The queued action.
    function getQueuedAction(uint64 actionId_) external view returns (QueuedAction memory action);

    /// @notice Get the number of sub-actions stored for a queued action.
    /// @dev    Reverts if:
    ///         - The action does not exist
    ///         - The action has already been executed
    ///         - The action has been cancelled
    ///
    /// @param  actionId_ The queued action ID.
    /// @return length   The number of sub-actions stored for the action.
    function getQueuedActionLength(uint64 actionId_) external view returns (uint256 length);

    /// @notice Get a single sub-action of a queued action.
    /// @dev    Reverts if:
    ///         - The action does not exist
    ///         - The action has already been executed
    ///         - The action has been cancelled
    ///         - The sub-action index is out of bounds
    ///
    /// @param  actionId_ The queued action ID.
    /// @param  index_    The sub-action index.
    /// @return target    The contract expected to receive the sub-action.
    /// @return selector  The function selector for the sub-action.
    /// @return payload   Encoded parameters for the sub-action.
    function getQueuedSubAction(
        uint64 actionId_,
        uint256 index_
    ) external view returns (address target, bytes4 selector, bytes memory payload);

    /// @notice Execute a queued action after its timelock has elapsed.
    /// @dev    Implementations must revert from implementation-specific hooks if the caller or
    ///         any sub-action should not be executed. Standard action state and timestamp
    ///         checks revert from the abstract implementation. The batch is atomic: a revert
    ///         in any sub-action reverts the entire batch. Cross-batch ordering is not
    ///         enforced: once their timelocks elapse, separately queued actions may be
    ///         executed in any order, regardless of the order in which they were queued.
    ///
    /// @param  actionId_ The queued action ID.
    function executeQueuedAction(uint64 actionId_) external;

    /// @notice Cancel a queued action.
    /// @dev    Implementations must revert from implementation-specific hooks if the caller
    ///         is not authorized to cancel the queued action.
    ///
    /// @param  actionId_ The queued action ID.
    function cancelQueuedAction(uint64 actionId_) external;
}
