// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";

contract TimelockBatchQueueSetTimelockDelayTest is TimelockBatchQueueTest {
    function test_setTimelockDelay_givenDelayBelowMinimum_reverts() public {
        _expectInvalidDelay(queue.MIN_DELAY() - 1);
    }

    function test_setTimelockDelay_givenDelayAboveMaximum_reverts() public {
        _expectInvalidDelay(queue.MAX_DELAY() + 1);
    }

    function test_setTimelockDelay_whenDelayIsMinimum() public {
        _setValidDelay(queue.MIN_DELAY());
    }

    function test_setTimelockDelay_whenDelayIsMaximum() public {
        _setValidDelay(queue.MAX_DELAY());
    }

    function test_setTimelockDelay_whenDelayIsInterior() public {
        _setValidDelay(5 days);
    }

    function _setValidDelay(uint48 delay_) internal {
        vm.expectEmit(false, false, false, true);
        emit ITimelockBatchQueue.TimelockDelaySet(delay_);
        queue.setTimelockDelay(delay_);
        assertEq(queue.timelockDelay(), delay_, "timelock delay");
    }

    function test_setTimelockDelay_doesNotChangeExistingActionTimestamps() public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory before_ = queue.getQueuedAction(actionId);

        queue.setTimelockDelay(10 days);

        ITimelockBatchQueue.QueuedAction memory after_ = queue.getQueuedAction(actionId);
        assertEq(after_.executableAt, before_.executableAt, "executableAt unchanged");
        assertEq(after_.expiresAt, before_.expiresAt, "expiresAt unchanged");
        assertEq(
            after_.executableAt,
            before_.queuedAt + TIMELOCK_DELAY,
            "original executableAt formula"
        );
        assertEq(queue.timelockDelay(), 10 days, "updated timelock delay");
    }

    function _expectInvalidDelay(uint48 delay_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                delay_,
                queue.MIN_DELAY(),
                queue.MAX_DELAY()
            )
        );
        queue.setTimelockDelay(delay_);
    }
}
