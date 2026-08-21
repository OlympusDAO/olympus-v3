// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ConfigTimelockBatchQueueTest} from "src/test/policies/utils/ConfigTimelockBatchQueue/ConfigTimelockBatchQueueTest.sol";
import {ConfigTimelockBatchQueueHarness} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/ConfigTimelockBatchQueueHarness.sol";
import {MockConfigTarget} from "src/test/policies/utils/ConfigTimelockBatchQueue/fixtures/MockConfigTarget.sol";

contract ConfigTimelockBatchQueueQueueConfigTest is ConfigTimelockBatchQueueTest {
    function test_queueConfig_reservesEveryKeyAndStoresStateHashes() public {
        uint64 actionId = _queue.queueConfig(_keys(_KEY_A, _KEY_B), _values(11, 22), 1);

        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), actionId, "first key owner");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), actionId, "second key owner");
        assertEq(_queue.getQueuedConfigStateCount(actionId, 0), 2, "stored guard count");

        (bytes32 keyA, bytes32 hashA) = _queue.getQueuedConfigState(actionId, 0, 0);
        (bytes32 keyB, bytes32 hashB) = _queue.getQueuedConfigState(actionId, 0, 1);
        assertEq(keyA, _scopedKey(_KEY_A), "first scoped key");
        assertEq(hashA, keccak256(abi.encode(_KEY_A, uint256(10))), "first state hash");
        assertEq(keyB, _scopedKey(_KEY_B), "second scoped key");
        assertEq(hashB, keccak256(abi.encode(_KEY_B, uint256(20))), "second state hash");
    }

    function test_queueConfig_emitsOneEventPerKey() public {
        vm.expectEmit(true, true, true, true);
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            1,
            0,
            _scopedKey(_KEY_A),
            0,
            address(_target),
            keccak256(abi.encode(_KEY_A, uint256(10)))
        );
        vm.expectEmit(true, true, true, true);
        emit IConfigTimelockBatchQueue.ConfigStateQueued(
            1,
            0,
            _scopedKey(_KEY_B),
            1,
            address(_target),
            keccak256(abi.encode(_KEY_B, uint256(20)))
        );
        _queue.queueConfig(_keys(_KEY_A, _KEY_B), _values(11, 22), 1);
    }

    function test_queueConfig_givenNoKeys_revertsWithoutQueueState() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeysEmpty.selector,
                uint64(1),
                uint256(0)
            )
        );
        _queue.queueConfig(new bytes32[](0), new uint256[](0), 1);
        assertEq(_queue.nextActionId(), 1, "action id not consumed");
    }

    function test_queueConfig_givenZeroKey_revertsWithoutQueueState() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyZero.selector,
                uint64(1),
                uint256(0),
                uint256(0)
            )
        );
        _queue.queueConfig(_keys(bytes32(0)), _values(11), 1);
        assertEq(_queue.nextActionId(), 1, "action id not consumed");
    }

    function test_queueConfig_givenZeroDestination_revertsWithoutQueueState() public {
        _queue.setConfigDestination(MockConfigTarget(address(0)));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigDestinationZero.selector,
                uint64(1),
                uint256(0)
            )
        );
        _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        assertEq(_queue.nextActionId(), 1, "action id not consumed");
    }

    function test_queueConfig_givenDuplicateKeysInOneSubAction_revertsWithoutLeakingGuards()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(_KEY_A),
                uint64(1)
            )
        );
        _queue.queueConfig(_keys(_KEY_A, _KEY_A), _values(11, 12), 1);

        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), 0, "duplicate key not leaked");
        assertEq(_queue.getQueuedConfigStateCount(1, 0), 0, "duplicate guards rolled back");
        assertEq(_queue.nextActionId(), 1, "action id not consumed");
    }

    function test_queueConfig_givenPendingKey_revertsWithOwningAction() public {
        uint64 owner = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(_KEY_A),
                owner
            )
        );
        _queue.queueConfig(_keys(_KEY_A), _values(12), 2);
    }

    function test_givenExpiredOwner_whenKeyIsQueued_reverts() public {
        uint64 owner = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        vm.warp(uint256(_queue.getQueuedAction(owner).expiresAt) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(_KEY_A),
                owner
            )
        );
        _queue.queueConfig(_keys(_KEY_A), _values(12), 2);

        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), owner, "expired owner retains key");
        assertEq(_queue.nextActionId(), owner + 1, "failed queue does not consume action id");
    }

    function test_queueConfig_givenLaterKeyIsPending_rollsBackEarlierAcquisition() public {
        uint64 owner = _queue.queueConfig(_keys(_KEY_B), _values(22), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                _scopedKey(_KEY_B),
                owner
            )
        );
        _queue.queueConfig(_keys(_KEY_A, _KEY_B), _values(11, 23), 2);

        assertEq(
            _queue.pendingActionId(_scopedKey(_KEY_A)),
            0,
            "earlier key acquisition rolled back"
        );
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), owner, "existing owner retained");
        assertEq(
            _queue.getQueuedConfigStateCount(owner + 1, 0),
            0,
            "failed action guards rolled back"
        );
        assertEq(_queue.nextActionId(), owner + 1, "action id not consumed");
    }

    function test_queueConfig_givenDifferentPendingKey_succeeds() public {
        uint64 actionA = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        uint64 actionB = _queue.queueConfig(_keys(_KEY_B), _values(22), 2);
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_A)), actionA, "first key owner");
        assertEq(_queue.pendingActionId(_scopedKey(_KEY_B)), actionB, "second key owner");
    }

    function test_queueConfig_givenSameLocalKeyForDifferentDestination_succeeds() public {
        uint64 first = _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        MockConfigTarget newDestination = new MockConfigTarget();
        newDestination.setConfigState(_KEY_A, 20);
        _queue.setConfigDestination(newDestination);

        uint64 second = _queue.queueConfig(_keys(_KEY_A), _values(21), 2);

        assertEq(
            _queue.pendingActionId(_scopedKey(address(_target), _KEY_A)),
            first,
            "original destination owner"
        );
        assertEq(
            _queue.pendingActionId(_scopedKey(address(newDestination), _KEY_A)),
            second,
            "new destination owner"
        );
    }

    function test_queueConfig_givenQueueValidationRejects_revertsBeforeAcquiringKeys() public {
        _queue.setQueueCaller(address(0xBEEF));
        vm.expectRevert(
            ConfigTimelockBatchQueueHarness.ConfigTimelockBatchQueueHarness_ActionInvalid.selector
        );
        _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        assertEq(
            _queue.pendingActionId(_scopedKey(_KEY_A)),
            0,
            "validation failure acquires no key"
        );
        assertEq(_queue.nextActionId(), 1, "action id not consumed");
    }

    function test_queueConfig_givenSubActionValidationRejects_revertsBeforeAcquiringKeys() public {
        _queue.setRejectSubAction(true);
        vm.expectRevert(
            ConfigTimelockBatchQueueHarness.ConfigTimelockBatchQueueHarness_ActionInvalid.selector
        );
        _queue.queueConfig(_keys(_KEY_A), _values(11), 1);
        assertEq(
            _queue.pendingActionId(_scopedKey(_KEY_A)),
            0,
            "validation failure acquires no key"
        );
        assertEq(_queue.nextActionId(), 1, "action id not consumed");
    }
}
