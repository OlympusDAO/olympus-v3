// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {ConfigTimelockBatchQueueHarness} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/ConfigTimelockBatchQueueHarness.sol";
import {MockConfigTarget} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/MockConfigTarget.sol";

abstract contract ConfigTimelockBatchQueueTest is Test {
    bytes32 internal constant KEY_A = keccak256("KEY_A");
    bytes32 internal constant KEY_B = keccak256("KEY_B");
    bytes32 internal constant KEY_C = keccak256("KEY_C");

    MockConfigTarget internal target;
    ConfigTimelockBatchQueueHarness internal queue;

    function setUp() public virtual {
        target = new MockConfigTarget();
        queue = new ConfigTimelockBatchQueueHarness(target);
        target.setConfigState(KEY_A, 10);
        target.setConfigState(KEY_B, 20);
        target.setConfigState(KEY_C, 30);
    }

    function _warpReady(uint64 actionId_) internal {
        vm.warp(queue.getQueuedAction(actionId_).executableAt);
    }

    function _scopedKey(bytes32 localKey_) internal view returns (bytes32 key) {
        return _scopedKey(address(target), localKey_);
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
        actions[0] = queue.makeAction(_keys(keyA_), _values(11), 1);
        actions[1] = queue.makeAction(_keys(keyB_), _values(22), 2);
    }
}
