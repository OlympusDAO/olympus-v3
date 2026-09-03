// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";

contract ConfigTimelockBatchQueueGetQueuedConfigStateTest is ConfigTimelockBatchQueueTest {
    function test_getQueuedConfigState_returnsStoredKeyAndHash() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A, _KEY_B), _values(11, 22), 1);
        (bytes32 key, bytes32 stateHash) = _queue.getQueuedConfigState(actionId, 0, 1);
        assertEq(key, _scopedKey(_KEY_B), "stored scoped key");
        assertEq(stateHash, keccak256(abi.encode(_KEY_B, uint256(20))), "stored state hash");
    }

    function test_getQueuedConfigState_givenUnknownAction_reverts() public {
        _expectOutOfBounds(99, 0, 0, 0);
    }

    function test_getQueuedConfigState_givenUnknownSubAction_reverts() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        _expectOutOfBounds(actionId, 1, 0, 0);
    }

    function test_getQueuedConfigState_givenOutOfBoundsConfigStateIndex_reverts() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        _expectOutOfBounds(actionId, 0, 1, 1);
    }

    function test_getQueuedConfigState_afterExecution_reverts() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        _warpReady(actionId);
        _queue.executeQueuedAction(actionId);
        _expectOutOfBounds(actionId, 0, 0, 0);
    }

    function test_getQueuedConfigState_afterCancellation_reverts() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        _queue.cancelQueuedAction(actionId);
        _expectOutOfBounds(actionId, 0, 0, 0);
    }

    function _expectOutOfBounds(
        uint64 actionId_,
        uint256 index_,
        uint256 configStateIndex_,
        uint256 length_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue
                    .IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds
                    .selector,
                actionId_,
                index_,
                configStateIndex_,
                length_
            )
        );
        _queue.getQueuedConfigState(actionId_, index_, configStateIndex_);
    }
}
