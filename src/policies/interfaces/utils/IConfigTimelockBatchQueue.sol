// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title IConfigTimelockBatchQueue
/// @notice Interface for configuration timelocks that prevent conflicting queued changes and
///         reject execution when the underlying configuration changed after queueing.
interface IConfigTimelockBatchQueue is ITimelockBatchQueue {
    // ========== EVENTS ========== //

    /// @notice Emitted when a sub-action reserves a configuration key.
    event ConfigStateQueued(
        uint64 indexed actionId,
        uint256 indexed index,
        bytes32 indexed key,
        uint256 configStateIndex,
        address destination,
        bytes32 expectedStateHash
    );

    // ========== ERRORS ========== //

    error IConfigTimelockBatchQueue_ConfigKeysEmpty(uint64 actionId, uint256 index);
    error IConfigTimelockBatchQueue_ConfigKeyZero(
        uint64 actionId,
        uint256 index,
        uint256 configStateIndex
    );
    error IConfigTimelockBatchQueue_ConfigKeyPending(bytes32 key, uint64 pendingActionId);
    error IConfigTimelockBatchQueue_ConfigKeysTooMany(uint256 length, uint256 maximum);
    error IConfigTimelockBatchQueue_ConfigDestinationZero(uint64 actionId, uint256 index);
    error IConfigTimelockBatchQueue_ConfigDestinationChanged(
        uint64 actionId,
        uint256 index,
        address expectedDestination,
        address currentDestination
    );
    error IConfigTimelockBatchQueue_ConfigStateChanged(
        uint64 actionId,
        uint256 index,
        bytes32 key,
        bytes32 expectedStateHash,
        bytes32 currentStateHash
    );
    error IConfigTimelockBatchQueue_ConfigKeyOwnershipInvalid(
        uint64 actionId,
        uint256 index,
        bytes32 key,
        uint64 pendingActionId
    );
    error IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds(
        uint64 actionId,
        uint256 index,
        uint256 configStateIndex,
        uint256 length
    );

    // ========== QUEUE STATE ========== //

    /// @notice Return the unresolved action that owns a destination-scoped key, or zero if free.
    function pendingActionId(bytes32 key_) external view returns (uint64 actionId);

    /// @notice Return the maximum total configuration keys a batch may reserve.
    function maxConfigKeysPerBatch() external view returns (uint256 maximum);

    /// @notice Return the number of configuration guards stored for a sub-action.
    function getQueuedConfigStateCount(
        uint64 actionId_,
        uint256 index_
    ) external view returns (uint256 length);

    /// @notice Return the destination selected by the subclass when a sub-action was queued.
    function getQueuedConfigDestination(
        uint64 actionId_,
        uint256 index_
    ) external view returns (address destination);

    /// @notice Return a stored destination-scoped key and its queue-time canonical state hash.
    function getQueuedConfigState(
        uint64 actionId_,
        uint256 index_,
        uint256 configStateIndex_
    ) external view returns (bytes32 key, bytes32 expectedStateHash);
}
