// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {MockConfigTarget} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/MockConfigTarget.sol";

contract ConfigTimelockBatchQueueHarness is ConfigTimelockBatchQueue {
    error ConfigTimelockBatchQueueHarness_ActionInvalid();
    error ConfigTimelockBatchQueueHarness_BatchRejected();

    uint48 internal constant _TIMELOCK_DELAY = 1 days;
    uint48 internal constant _EXECUTION_WINDOW = 7 days;

    MockConfigTarget public configDestination;

    uint256 public maxConfigKeys = 4;
    bool public rejectBatch;
    bool public rejectSubAction;
    address public queueCaller;
    mapping(uint256 index => bool rejected) public rejectedSubActionIndexes;
    mapping(bytes32 key => bytes32 dependencyKey) public stateHashDependencies;

    constructor(MockConfigTarget target_) ConfigTimelockBatchQueue(_TIMELOCK_DELAY) {
        configDestination = target_;
    }

    function queueConfig(
        bytes32[] memory keys_,
        uint256[] memory values_,
        uint256 marker_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(configDestination),
                MockConfigTarget.applyConfig.selector,
                abi.encode(keys_, values_, marker_)
            );
    }

    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId) {
        return _queueAction(actions_);
    }

    function makeAction(
        bytes32[] memory keys_,
        uint256[] memory values_,
        uint256 marker_
    ) external view returns (ITimelockBatchQueue.BatchAction memory action) {
        return
            ITimelockBatchQueue.BatchAction({
                target: address(configDestination),
                selector: MockConfigTarget.applyConfig.selector,
                payload: abi.encode(keys_, values_, marker_)
            });
    }

    function setMaxConfigKeys(uint256 maximum_) external {
        maxConfigKeys = maximum_;
    }

    function setConfigDestination(MockConfigTarget destination_) external {
        configDestination = destination_;
    }

    function setRejectBatch(bool rejectBatch_) external {
        rejectBatch = rejectBatch_;
    }

    function setRejectSubAction(bool rejectSubAction_) external {
        rejectSubAction = rejectSubAction_;
    }

    function setRejectedSubActionIndex(uint256 index_, bool rejected_) external {
        rejectedSubActionIndexes[index_] = rejected_;
    }

    function setStateHashDependency(bytes32 key_, bytes32 dependencyKey_) external {
        stateHashDependencies[key_] = dependencyKey_;
    }

    function setQueueCaller(address caller_) external {
        queueCaller = caller_;
    }

    function _validateConfigQueue(address caller_) internal view override {
        if (queueCaller != address(0) && caller_ != queueCaller) {
            revert ConfigTimelockBatchQueueHarness_ActionInvalid();
        }
    }

    function _validateConfigSubAction(
        address,
        uint64,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        if (rejectSubAction || rejectedSubActionIndexes[index_]) {
            revert ConfigTimelockBatchQueueHarness_ActionInvalid();
        }
        if (
            action_.target != address(configDestination) ||
            action_.selector != MockConfigTarget.applyConfig.selector
        ) {
            revert ConfigTimelockBatchQueueHarness_ActionInvalid();
        }

        (bytes32[] memory keys, uint256[] memory values, ) = abi.decode(
            action_.payload,
            (bytes32[], uint256[], uint256)
        );
        if (keys.length != values.length) {
            revert ConfigTimelockBatchQueueHarness_ActionInvalid();
        }
    }

    function _configKeys(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure override returns (bytes32[] memory keys) {
        (keys, , ) = abi.decode(action_.payload, (bytes32[], uint256[], uint256));
    }

    function _configDestination(
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (address destination) {
        return address(configDestination);
    }

    function _currentConfigStateHash(
        uint64,
        uint256,
        bytes32 key_,
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (bytes32 stateHash) {
        bytes32 dependencyKey = stateHashDependencies[key_];
        bytes32 stateKey = dependencyKey == bytes32(0) ? key_ : dependencyKey;
        return keccak256(abi.encode(key_, configDestination.configState(stateKey)));
    }

    function _validateConfigBatch(
        address,
        uint64,
        ITimelockBatchQueue.BatchAction[] memory
    ) internal view override {
        if (rejectBatch) revert ConfigTimelockBatchQueueHarness_BatchRejected();
    }

    function _executeConfigSubAction(
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        (bool success, bytes memory returnData) = action_.target.call(
            abi.encodePacked(action_.selector, action_.payload)
        );
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {}

    function _validateCancellation(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {}

    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ != _TIMELOCK_DELAY) {
            revert ITimelockBatchQueue_TimelockDelayInvalid(
                delay_,
                _TIMELOCK_DELAY,
                _TIMELOCK_DELAY
            );
        }
    }

    function _executionWindow() internal pure override returns (uint48 executionWindow) {
        return _EXECUTION_WINDOW;
    }

    function _maxConfigKeysPerBatch() internal view override returns (uint256 maximum) {
        return maxConfigKeys == 0 ? super._maxConfigKeysPerBatch() : maxConfigKeys;
    }
}
