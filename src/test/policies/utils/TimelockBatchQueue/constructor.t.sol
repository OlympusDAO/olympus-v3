// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {TimelockBatchQueueTest} from "src/test/policies/utils/TimelockBatchQueue/TimelockBatchQueueTest.sol";
import {MockTimelockBatchQueue} from "src/test/policies/utils/TimelockBatchQueue/fixtures/MockTimelockBatchQueue.sol";

contract TimelockBatchQueueConstructorTest is TimelockBatchQueueTest {
    function test_constructor_setsInitialState() public view {
        assertEq(queue.timelockDelay(), TIMELOCK_DELAY, "Timelock delay");
        assertEq(queue.nextActionId(), 1, "Next action ID");
    }

    function test_constructor_givenDelayBelowMinimum_reverts() public {
        uint48 delay = queue.MIN_DELAY() - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                delay,
                queue.MIN_DELAY(),
                queue.MAX_DELAY()
            )
        );
        new MockTimelockBatchQueue(delay);
    }

    function test_constructor_givenDelayAboveMaximum_reverts() public {
        uint48 delay = queue.MAX_DELAY() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                delay,
                queue.MIN_DELAY(),
                queue.MAX_DELAY()
            )
        );
        new MockTimelockBatchQueue(delay);
    }

    function test_constructor_givenBoundaryDelays_succeeds() public {
        assertEq(new MockTimelockBatchQueue(queue.MIN_DELAY()).timelockDelay(), queue.MIN_DELAY());
        assertEq(new MockTimelockBatchQueue(queue.MAX_DELAY()).timelockDelay(), queue.MAX_DELAY());
    }

    function test_constructor_emitsTimelockDelaySet() public {
        uint48 delay = 3 days;
        vm.expectEmit(false, false, false, true);
        emit ITimelockBatchQueue.TimelockDelaySet(delay);
        new MockTimelockBatchQueue(delay);
    }
}
