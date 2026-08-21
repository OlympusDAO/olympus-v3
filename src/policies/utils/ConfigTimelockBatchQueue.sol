// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Interfaces
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

/// @title ConfigTimelockBatchQueue
/// @notice Base contract for configuration timelocks. It prevents conflicting changes from being
///         queued together and prevents queued changes from executing after their underlying
///         configuration has changed.
/// @dev    Each sub-action identifies its destination and the configuration it depends on with one
///         or more keys. The contract scopes every key to that destination, reserves the scoped
///         keys, and records their current state hashes at queue time. A reserved key cannot be
///         used by another unresolved action. At execution, the destination and every current
///         state hash must still match. Keys are released only after the whole batch executes or
///         is cancelled. Product contracts customize validation, destinations, keys, hashes, and
///         dispatch through the config-specific hooks below.
abstract contract ConfigTimelockBatchQueue is TimelockBatchQueue, IConfigTimelockBatchQueue {
    struct QueuedConfigState {
        bytes32 localKey;
        bytes32 expectedStateHash;
    }

    mapping(bytes32 key => uint64 actionId) private _pendingActionIds;
    mapping(uint64 actionId => mapping(uint256 index => QueuedConfigState[] states))
        private _queuedConfigStates;
    mapping(uint64 actionId => mapping(uint256 index => address destination))
        private _queuedConfigDestinations;

    constructor(uint48 initialTimelockDelay_) TimelockBatchQueue(initialTimelockDelay_) {}

    /// @inheritdoc IConfigTimelockBatchQueue
    function pendingActionId(bytes32 key_) external view returns (uint64 actionId) {
        return _pendingActionIds[key_];
    }

    /// @inheritdoc IConfigTimelockBatchQueue
    function maxConfigKeysPerBatch() external view returns (uint256 maximum) {
        return _maxConfigKeysPerBatch();
    }

    /// @inheritdoc IConfigTimelockBatchQueue
    function getQueuedConfigStateCount(
        uint64 actionId_,
        uint256 index_
    ) external view returns (uint256 length) {
        return _queuedConfigStates[actionId_][index_].length;
    }

    /// @inheritdoc IConfigTimelockBatchQueue
    function getQueuedConfigDestination(
        uint64 actionId_,
        uint256 index_
    ) external view returns (address destination) {
        return _queuedConfigDestinations[actionId_][index_];
    }

    /// @inheritdoc IConfigTimelockBatchQueue
    function getQueuedConfigState(
        uint64 actionId_,
        uint256 index_,
        uint256 configStateIndex_
    ) external view returns (bytes32 key, bytes32 expectedStateHash) {
        QueuedConfigState[] storage states = _queuedConfigStates[actionId_][index_];
        uint256 length = states.length;
        if (configStateIndex_ >= length) {
            revert IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds(
                actionId_,
                index_,
                configStateIndex_,
                length
            );
        }

        QueuedConfigState storage state = states[configStateIndex_];
        address destination = _queuedConfigDestinations[actionId_][index_];
        return (_scopeConfigKey(destination, state.localKey), state.expectedStateHash);
    }

    function _onSubActionQueued(
        address caller_,
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        if (index_ == 0) _validateConfigQueue(caller_);
        _validateConfigSubAction(caller_, actionId_, index_, action_);

        address destination = _configDestination(action_);
        if (destination == address(0)) {
            revert IConfigTimelockBatchQueue_ConfigDestinationZero(actionId_, index_);
        }
        _queuedConfigDestinations[actionId_][index_] = destination;

        bytes32[] memory keys = _configKeys(action_);
        uint256 keyLength = keys.length;
        if (keyLength == 0) {
            revert IConfigTimelockBatchQueue_ConfigKeysEmpty(actionId_, index_);
        }

        uint256 newKeyCount = _queuedConfigKeyCount(actionId_, index_) + keyLength;
        uint256 maximum = _maxConfigKeysPerBatch();
        if (newKeyCount > maximum) {
            revert IConfigTimelockBatchQueue_ConfigKeysTooMany(newKeyCount, maximum);
        }

        for (uint256 i; i < keyLength; ++i) {
            bytes32 localKey = keys[i];
            if (localKey == bytes32(0)) {
                revert IConfigTimelockBatchQueue_ConfigKeyZero(actionId_, index_, i);
            }

            bytes32 key = _scopeConfigKey(destination, localKey);

            uint64 owner = _pendingActionIds[key];
            if (owner != 0) {
                revert IConfigTimelockBatchQueue_ConfigKeyPending(key, owner);
            }

            bytes32 expectedStateHash = _currentConfigStateHash(
                actionId_,
                index_,
                localKey,
                action_
            );
            _queuedConfigStates[actionId_][index_].push(
                QueuedConfigState({localKey: localKey, expectedStateHash: expectedStateHash})
            );
            _pendingActionIds[key] = actionId_;

            emit ConfigStateQueued(actionId_, index_, key, i, destination, expectedStateHash);
        }
    }

    function _onBatchQueued(
        address caller_,
        uint64 actionId_,
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal view override {
        _validateConfigBatch(caller_, actionId_, actions_);
    }

    function _executeSubAction(
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        address expectedDestination = _queuedConfigDestinations[actionId_][index_];
        address currentDestination = _configDestination(action_);
        if (currentDestination != expectedDestination) {
            revert IConfigTimelockBatchQueue_ConfigDestinationChanged(
                actionId_,
                index_,
                expectedDestination,
                currentDestination
            );
        }

        QueuedConfigState[] storage states = _queuedConfigStates[actionId_][index_];
        uint256 length = states.length;
        for (uint256 i; i < length; ++i) {
            QueuedConfigState storage state = states[i];
            bytes32 key = _scopeConfigKey(expectedDestination, state.localKey);
            uint64 owner = _pendingActionIds[key];
            if (owner != actionId_) {
                revert IConfigTimelockBatchQueue_ConfigKeyOwnershipInvalid(
                    actionId_,
                    index_,
                    key,
                    owner
                );
            }

            bytes32 currentStateHash = _currentConfigStateHash(
                actionId_,
                index_,
                state.localKey,
                action_
            );
            if (currentStateHash != state.expectedStateHash) {
                revert IConfigTimelockBatchQueue_ConfigStateChanged(
                    actionId_,
                    index_,
                    key,
                    state.expectedStateHash,
                    currentStateHash
                );
            }
        }

        _executeConfigSubAction(actionId_, index_, action_);
    }

    function _onActionExecuted(uint64 actionId_, uint256 subActionCount_) internal override {
        _releaseConfigKeys(actionId_, subActionCount_);
    }

    function _onActionCancelled(uint64 actionId_, uint256 subActionCount_) internal override {
        _releaseConfigKeys(actionId_, subActionCount_);
    }

    function _releaseConfigKeys(uint64 actionId_, uint256 subActionCount_) private {
        for (uint256 index; index < subActionCount_; ++index) {
            QueuedConfigState[] storage states = _queuedConfigStates[actionId_][index];
            address destination = _queuedConfigDestinations[actionId_][index];
            uint256 length = states.length;
            for (uint256 i; i < length; ++i) {
                bytes32 key = _scopeConfigKey(destination, states[i].localKey);
                uint64 owner = _pendingActionIds[key];
                if (owner != actionId_) {
                    revert IConfigTimelockBatchQueue_ConfigKeyOwnershipInvalid(
                        actionId_,
                        index,
                        key,
                        owner
                    );
                }
                delete _pendingActionIds[key];
            }
            delete _queuedConfigStates[actionId_][index];
            delete _queuedConfigDestinations[actionId_][index];
        }
    }

    function _queuedConfigKeyCount(
        uint64 actionId_,
        uint256 endIndex_
    ) private view returns (uint256 count) {
        for (uint256 index; index < endIndex_; ++index) {
            count += _queuedConfigStates[actionId_][index].length;
        }
    }

    function _scopeConfigKey(
        address destination_,
        bytes32 localKey_
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(destination_, localKey_));
    }

    /// @notice Validates queue-wide authorization and lifecycle requirements.
    /// @dev Called once, before the first sub-action acquires configuration keys. Implementations
    ///      must revert when the caller or current product lifecycle cannot queue the batch.
    /// @param caller_ Account queueing the batch.
    function _validateConfigQueue(address caller_) internal view virtual;

    /// @notice Validates one sub-action before its destination and configuration keys are stored.
    /// @dev Implementations must revert for unsupported targets, selectors, payloads, or product
    ///      state. Any state recorded by an earlier sub-action is rolled back if validation fails.
    /// @param caller_ Account queueing the batch.
    /// @param actionId_ Action ID reserved for the batch.
    /// @param index_ Position of the sub-action within the batch.
    /// @param action_ Sub-action to validate.
    function _validateConfigSubAction(
        address caller_,
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view virtual;

    /// @notice Selects the destination that namespaces this sub-action's configuration keys.
    /// @dev    The base stores this address at queue time and requires the hook to return the same
    ///         address at execution. Returning a new address after rotation creates a distinct key
    ///         namespace for new actions and makes existing actions non-executable.
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view virtual returns (address destination);

    /// @notice Selects the destination-local configuration domains used by a sub-action.
    /// @dev    The base rejects zero or duplicate local keys and scopes every key with the address
    ///         returned by `_configDestination` before acquiring ownership.
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view virtual returns (bytes32[] memory keys);

    /// @notice Hashes the live configuration state guarded by one local key.
    /// @dev Called when queueing to store the expected hash and again immediately before execution
    ///      to detect stale state. Implementations must hash the same canonical fields on both
    ///      paths and exclude values that may legitimately change during the timelock delay.
    /// @param actionId_ ID of the queued action.
    /// @param index_ Position of the sub-action within the batch.
    /// @param key_ Destination-local configuration key being guarded.
    /// @param action_ Sub-action whose live configuration state is hashed.
    /// @return stateHash Canonical hash of the guarded live state.
    function _currentConfigStateHash(
        uint64 actionId_,
        uint256 index_,
        bytes32 key_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view virtual returns (bytes32 stateHash);

    /// @notice Validates invariants spanning the complete batch after all guards are acquired.
    /// @dev The default implementation is a no-op. An override must revert on invalid cross-action
    ///      state; the revert rolls back every guard acquired for the batch.
    /// @param caller_ Account queueing the batch.
    /// @param actionId_ Action ID reserved for the batch.
    /// @param actions_ Complete ordered set of queued sub-actions.
    function _validateConfigBatch(
        address caller_,
        uint64 actionId_,
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) internal view virtual {}

    /// @dev Subclasses must not perform a state-changing external call before the intended
    ///      target dispatch. Such a call could make the already-validated state stale.
    function _executeConfigSubAction(
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal virtual;

    /// @notice Maximum aggregate number of configuration keys a batch may reserve.
    /// @dev    Defaults to the maximum number of sub-actions. Products supporting composite
    ///         multi-domain sub-actions should override this batch-wide bound.
    function _maxConfigKeysPerBatch() internal view virtual returns (uint256 maximum) {
        return _maxBatchSize();
    }

    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(TimelockBatchQueue) returns (bool) {
        return
            interfaceId_ == type(IConfigTimelockBatchQueue).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
