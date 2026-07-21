// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {YRFTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YRFTimelock/YRFTimelockTestBase.sol";

contract YRFTimelockTests_SetTimelockDelay is YRFTimelockTestBase {
    // setTimelockDelay
    // given the caller does not hold the admin role
    //  when setting the delay
    //   then it reverts with ROLES_RequireRole(admin)
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != guardian);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        yrfTimelock.setTimelockDelay(2 days);
    }

    // setTimelockDelay
    // given the caller holds only the yrf_admin role
    //  when setting the delay
    //   then it reverts with ROLES_RequireRole(admin)
    function test_givenYrfAdminCaller_reverts() public {
        vm.prank(yrfAdmin);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        yrfTimelock.setTimelockDelay(2 days);
    }

    // setTimelockDelay
    // given the delay is below MIN_TIMELOCK_DELAY
    //  when the admin sets any such delay
    //   then it reverts with ITimelockBatchQueue_TimelockDelayInvalid
    function test_givenDelayBelowMinimum_reverts(uint48 delay_) public {
        uint48 minDelay = yrfTimelock.MIN_TIMELOCK_DELAY();
        uint48 maxDelay = yrfTimelock.MAX_TIMELOCK_DELAY();
        delay_ = uint48(bound(delay_, 0, minDelay - 1));

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                delay_,
                minDelay,
                maxDelay
            )
        );
        yrfTimelock.setTimelockDelay(delay_);
    }

    // setTimelockDelay
    // given the delay is above MAX_TIMELOCK_DELAY
    //  when the admin sets any such delay
    //   then it reverts with ITimelockBatchQueue_TimelockDelayInvalid
    function test_givenDelayAboveMaximum_reverts(uint48 delay_) public {
        uint48 minDelay = yrfTimelock.MIN_TIMELOCK_DELAY();
        uint48 maxDelay = yrfTimelock.MAX_TIMELOCK_DELAY();
        delay_ = uint48(bound(delay_, uint256(maxDelay) + 1, type(uint48).max));

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                delay_,
                minDelay,
                maxDelay
            )
        );
        yrfTimelock.setTimelockDelay(delay_);
    }

    // setTimelockDelay
    // given any delay within [MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY]
    //  when the admin sets the delay
    //   then the delay is updated and TimelockDelaySet is emitted
    function test_givenAdminCaller_setsDelayAndEmitsEvent(uint48 delay_) public {
        delay_ = uint48(
            bound(delay_, yrfTimelock.MIN_TIMELOCK_DELAY(), yrfTimelock.MAX_TIMELOCK_DELAY())
        );

        vm.expectEmit(false, false, false, true, address(yrfTimelock));
        emit ITimelockBatchQueue.TimelockDelaySet(delay_);
        vm.prank(guardian);
        yrfTimelock.setTimelockDelay(delay_);

        assertEq(yrfTimelock.timelockDelay(), delay_, "timelock delay");
    }

    // setTimelockDelay
    // given the timelock policy is disabled
    //  when the admin sets a valid delay
    //   then the delay is updated (configuration is allowed while disabled)
    function test_givenTimelockDisabled_setsDelay() public {
        vm.prank(guardian);
        yrfTimelock.disable("");

        vm.prank(guardian);
        yrfTimelock.setTimelockDelay(2 days);

        assertEq(yrfTimelock.timelockDelay(), 2 days, "timelock delay");
    }

    // setTimelockDelay
    // given an action was queued under the previous delay
    //  when the admin changes the delay
    //   then the queued action keeps its original executableAt and expiresAt,
    //   and a subsequently queued action uses the new delay
    function test_givenDelayChanged_alreadyQueuedActionKeepsQueuedTimestamps() public {
        uint48 queuedAt = uint48(vm.getBlockTimestamp());
        uint64 queuedActionId = _queueSetInitialDiscount(1e16);
        ITimelockBatchQueue.QueuedAction memory queued = yrfTimelock.getQueuedAction(
            queuedActionId
        );
        assertEq(queued.executableAt, queuedAt + yrfTimelockDelay, "executableAt before change");

        uint48 newDelay = 10 days;
        vm.prank(guardian);
        yrfTimelock.setTimelockDelay(newDelay);

        ITimelockBatchQueue.QueuedAction memory queuedAfter = yrfTimelock.getQueuedAction(
            queuedActionId
        );
        assertEq(queuedAfter.executableAt, queued.executableAt, "executableAt unchanged");
        assertEq(queuedAfter.expiresAt, queued.expiresAt, "expiresAt unchanged");

        uint64 nextActionId = _queueIncreaseClearinghouseOffset(address(clearinghouse), 0);
        assertEq(
            yrfTimelock.getQueuedAction(nextActionId).executableAt,
            queuedAt + newDelay,
            "new action uses new delay"
        );
    }
}
