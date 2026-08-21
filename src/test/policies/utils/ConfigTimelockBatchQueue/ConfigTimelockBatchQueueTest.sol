// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {ConfigTimelockBatchQueueHarness} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/ConfigTimelockBatchQueueHarness.sol";
import {MockConfigTarget} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/MockConfigTarget.sol";

abstract contract ConfigTimelockBatchQueueTest is Test {
    bytes32 internal constant _KEY_A = keccak256("KEY_A");
    bytes32 internal constant _KEY_B = keccak256("KEY_B");
    bytes32 internal constant _KEY_C = keccak256("KEY_C");

    MockConfigTarget internal _target;
    ConfigTimelockBatchQueueHarness internal _queue;

    function setUp() public virtual {
        _target = new MockConfigTarget();
        _queue = new ConfigTimelockBatchQueueHarness(_target);
        _target.setConfigState(_KEY_A, 10);
        _target.setConfigState(_KEY_B, 20);
        _target.setConfigState(_KEY_C, 30);
    }

    function _warpReady(uint64 actionId_) internal {
        vm.warp(_queue.getQueuedAction(actionId_).executableAt);
    }

    function _scopedKey(bytes32 localKey_) internal view returns (bytes32 key) {
        return _scopedKey(address(_target), localKey_);
    }

    function _scopedKey(
        address destination_,
        bytes32 localKey_
    ) internal pure returns (bytes32 key) {
        return keccak256(abi.encode(destination_, localKey_));
    }

    function _keys(bytes32 key_) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](1);
        keys[0] = key_;
    }

    function _keys(bytes32 keyA_, bytes32 keyB_) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](2);
        keys[0] = keyA_;
        keys[1] = keyB_;
    }

    function _keys(
        bytes32 keyA_,
        bytes32 keyB_,
        bytes32 keyC_
    ) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](3);
        keys[0] = keyA_;
        keys[1] = keyB_;
        keys[2] = keyC_;
    }

    function _values(uint256 value_) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value_;
    }

    function _values(
        uint256 valueA_,
        uint256 valueB_
    ) internal pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = valueA_;
        values[1] = valueB_;
    }

    function _values(
        uint256 valueA_,
        uint256 valueB_,
        uint256 valueC_
    ) internal pure returns (uint256[] memory values) {
        values = new uint256[](3);
        values[0] = valueA_;
        values[1] = valueB_;
        values[2] = valueC_;
    }

    function _batch(
        bytes32 keyA_,
        bytes32 keyB_
    ) internal view returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _queue.makeAction(_keys(keyA_), _values(11), 1);
        actions[1] = _queue.makeAction(_keys(keyB_), _values(22), 2);
    }

    function _pendingActionIdSlot(bytes32 key_) internal pure returns (bytes32 slot) {
        return keccak256(abi.encode(key_, uint256(2)));
    }

    function _corruptPendingActionId(
        bytes32 key_,
        uint64 expectedOwner_,
        uint64 corruptOwner_
    ) internal {
        assertEq(_queue.pendingActionId(key_), expectedOwner_, "expected owner before corruption");
        vm.store(address(_queue), _pendingActionIdSlot(key_), bytes32(uint256(corruptOwner_)));
        assertEq(_queue.pendingActionId(key_), corruptOwner_, "corrupt owner after write");
    }
}
