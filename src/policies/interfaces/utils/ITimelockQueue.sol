// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title  ITimelockQueue
/// @notice Interface for contracts that queue, execute, and cancel timelocked actions.
/// @dev    Implementations are expected to enforce action-specific authorization and execution
///         checks in the concrete contract. Standard queued-action state checks, timestamp checks,
///         and terminal payload clearing are handled by the abstract implementation.
interface ITimelockQueue {
    // ========== EVENTS ========== //

    /// @notice Emitted when an action is queued.
    ///
    /// @param actionId     The queued action ID.
    /// @param target       The contract expected to receive the queued action.
    /// @param selector     The function selector for the queued action.
    /// @param proposer     The account that queued the action.
    /// @param payloadHash  Hash of the encoded action payload.
    /// @param executableAt Timestamp at which the action can first be executed.
    /// @param expiresAt    Timestamp after which the action can no longer be executed.
    event TimelockActionQueued(
        uint64 indexed actionId,
        address indexed target,
        bytes4 indexed selector,
        address proposer,
        bytes32 payloadHash,
        uint48 executableAt,
        uint48 expiresAt
    );

    /// @notice Emitted when a queued action is executed.
    ///
    /// @param actionId The queued action ID.
    /// @param target   The contract that received the queued action.
    /// @param selector The function selector for the queued action.
    /// @param executor The account that executed the action.
    event TimelockActionExecuted(
        uint64 indexed actionId,
        address indexed target,
        bytes4 indexed selector,
        address executor
    );

    /// @notice Emitted when a queued action is cancelled.
    ///
    /// @param actionId  The queued action ID.
    /// @param target    The contract that would have received the queued action.
    /// @param selector  The function selector for the queued action.
    /// @param canceller The account that cancelled the action.
    event TimelockActionCancelled(
        uint64 indexed actionId,
        address indexed target,
        bytes4 indexed selector,
        address canceller
    );

    /// @notice Emitted when the timelock delay is changed.
    ///
    /// @param delay The new timelock delay in seconds.
    event TimelockDelaySet(uint48 delay);

    // ========== ERRORS ========== //

    /// @notice Thrown when a queued action does not exist.
    ///
    /// @param actionId The queued action ID.
    error ITimelockQueue_ActionNotFound(uint64 actionId);

    /// @notice Thrown when a queued action has already been executed.
    ///
    /// @param actionId The queued action ID.
    error ITimelockQueue_ActionAlreadyExecuted(uint64 actionId);

    /// @notice Thrown when a queued action has been cancelled.
    ///
    /// @param actionId The queued action ID.
    error ITimelockQueue_ActionCancelled(uint64 actionId);

    /// @notice Thrown when a queued action is executed before its timelock has elapsed.
    ///
    /// @param actionId     The queued action ID.
    /// @param executableAt Timestamp at which the action can first be executed.
    error ITimelockQueue_ActionNotReady(uint64 actionId, uint48 executableAt);

    /// @notice Thrown when a queued action is executed after its execution window.
    ///
    /// @param actionId  The queued action ID.
    /// @param expiresAt Timestamp after which the action can no longer be executed.
    error ITimelockQueue_ActionExpired(uint64 actionId, uint48 expiresAt);

    /// @notice Thrown when a queued action has an unsupported target or selector.
    ///
    /// @param target   The queued target address.
    /// @param selector The queued function selector.
    error ITimelockQueue_ActionInvalid(address target, bytes4 selector);

    /// @notice Thrown when a proposed timelock delay is outside the accepted range.
    ///
    /// @param delay   The proposed delay.
    /// @param minimum The minimum accepted delay.
    /// @param maximum The maximum accepted delay.
    error ITimelockQueue_TimelockDelayInvalid(uint48 delay, uint48 minimum, uint48 maximum);

    // ========== DATA STRUCTURES ========== //

    /// @notice Queued timelock action.
    ///
    /// @param target       The contract expected to receive the queued action.
    /// @param selector     The function selector for the queued action.
    /// @param proposer     The account that queued the action.
    /// @param queuedAt     Timestamp at which the action was queued.
    /// @param executableAt Timestamp at which the action can first be executed.
    /// @param expiresAt    Timestamp after which the action can no longer be executed.
    /// @param executed     Whether the action has been executed.
    /// @param cancelled    Whether the action has been cancelled.
    /// @param payload      Encoded parameters for the action.
    struct QueuedAction {
        address target;
        bytes4 selector;
        address proposer;
        uint48 queuedAt;
        uint48 executableAt;
        uint48 expiresAt;
        bool executed;
        bool cancelled;
        bytes payload;
    }

    // ========== QUEUE STATE ========== //

    /// @notice Current timelock delay in seconds.
    function timelockDelay() external view returns (uint48);

    /// @notice Next queued action ID.
    function nextActionId() external view returns (uint64);

    /// @notice Get a queued action.
    /// @dev    Reverts if the action does not exist.
    ///
    /// @param  actionId_ The queued action ID.
    /// @return action_   The queued action.
    function getQueuedAction(uint64 actionId_) external view returns (QueuedAction memory action_);

    /// @notice Execute a queued action after its timelock has elapsed.
    /// @dev    Implementations must revert from implementation-specific hooks if the caller,
    ///         target, selector, or payload should not be executed. Standard action state and
    ///         timestamp checks revert from the abstract implementation.
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
