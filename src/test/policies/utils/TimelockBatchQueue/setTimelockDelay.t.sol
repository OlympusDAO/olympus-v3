// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";

contract TimelockBatchQueueSetTimelockDelayTest is TimelockBatchQueueTest {
    function test_setTimelockDelay_givenDelayBelowMinimum_reverts() public {
        _expectInvalidDelay(queue.MIN_DELAY() - 1);
    }

    function test_setTimelockDelay_givenDelayAboveMaximum_reverts() public {
        _expectInvalidDelay(queue.MAX_DELAY() + 1);
    }

    function test_setTimelockDelay_givenValidDelay_updatesStateAndEmits() public {
        uint48 delay = 5 days;
        vm.expectEmit(false, false, false, true);
        emit ITimelockBatchQueue.TimelockDelaySet(delay);
        queue.setTimelockDelay(delay);
        assertEq(queue.timelockDelay(), delay);
    }

    function test_setTimelockDelay_doesNotChangeExistingActionTimestamps() public {
        uint64 actionId = _queueSingleAction();
        ITimelockBatchQueue.QueuedAction memory before_ = queue.getQueuedAction(actionId);

        queue.setTimelockDelay(10 days);

        ITimelockBatchQueue.QueuedAction memory after_ = queue.getQueuedAction(actionId);
        assertEq(after_.executableAt, before_.executableAt);
        assertEq(after_.expiresAt, before_.expiresAt);
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
