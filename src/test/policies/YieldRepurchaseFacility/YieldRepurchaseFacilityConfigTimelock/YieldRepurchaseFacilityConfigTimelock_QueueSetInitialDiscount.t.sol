// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityConfigTimelock.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {YieldRepurchaseFacilityConfigTimelock} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityConfigTimelock.sol";
import {YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {YieldRepurchaseFacilityConfigTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityConfigTimelock/YieldRepurchaseFacilityConfigTimelockTestBase.sol";

contract YieldRepurchaseFacilityConfigTimelockTests_QueueSetInitialDiscount is
    YieldRepurchaseFacilityConfigTimelockTestBase
{
    // queueSetInitialDiscount
    // given the caller does not hold the yrf_admin role
    //  when queueing a discount update
    //   then it reverts with ROLES_RequireRole(yrf_admin)
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != yrfAdmin);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.queueSetInitialDiscount(1e16);
    }

    // queueSetInitialDiscount
    // given the caller holds only the admin role
    //  when queueing a discount update
    //   then it reverts (yrf_admin is the sole queue proposer)
    function test_givenAdminCaller_reverts() public {
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.queueSetInitialDiscount(1e16);
    }

    // queueSetInitialDiscount
    // given the timelock policy is disabled
    //  when queueing a discount update
    //   then it reverts with NotEnabled and no action id is consumed
    function test_givenTimelockDisabled_reverts() public {
        vm.prank(guardian);
        configTimelock.disable("");

        vm.prank(yrfAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.queueSetInitialDiscount(1e16);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueSetInitialDiscount
    // given the facility slot has not been set
    //  when queueing a discount update
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
    function test_givenFacilityNotSet_reverts() public {
        YieldRepurchaseFacilityConfigTimelock unwired = _deployUnwiredTimelock();

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityConfigTimelock
                .IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
                .selector
        );
        unwired.queueSetInitialDiscount(1e16);
    }

    // queueSetInitialDiscount
    // given the discount is exactly 100% (1e18)
    //  when queueing the discount
    //   then it reverts with IYieldRepurchaseFacilityV2_InitialDiscountTooHigh (exclusive bound)
    function test_givenDiscountAtOneHundredPercent_reverts() public {
        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InitialDiscountTooHigh.selector
        );
        configTimelock.queueSetInitialDiscount(1e18);
    }

    // queueSetInitialDiscount
    // given the discount is above 100% (1e18)
    //  when queueing any such discount
    //   then it reverts with IYieldRepurchaseFacilityV2_InitialDiscountTooHigh
    function test_givenDiscountAboveOneHundredPercent_reverts(uint256 discount_) public {
        discount_ = bound(discount_, 1e18 + 1, type(uint256).max);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InitialDiscountTooHigh.selector
        );
        configTimelock.queueSetInitialDiscount(discount_);
    }

    // queueSetInitialDiscount
    // given any discount below 100% (1e18)
    //  when the yrf_admin queues the discount
    //   then the action is stored with the queue events and timelock timestamps
    function test_givenYrfAdminCaller_whenDiscountIsValid_queuesAction(uint256 discount_) public {
        discount_ = bound(discount_, 0, 1e18 - 1);
        uint256 queuedAt = vm.getBlockTimestamp();
        ITimelockBatchQueue.BatchAction[] memory actions = _singleAction(
            address(yieldRepo),
            IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
            abi.encode(discount_)
        );

        _expectActionQueued(configTimelock, 1, yrfAdmin, actions);
        uint64 actionId = _queueSetInitialDiscount(discount_);

        assertEq(actionId, 1, "action id");
        _assertQueuedSingleAction(configTimelock, actionId, queuedAt, actions[0]);
    }

    // queueSetInitialDiscount
    // given a discount update is queued
    //  when reading pendingInitialDiscountActionId
    //   then it returns the queued action id
    function test_givenQueuedAction_recordsPendingSlot() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);

        assertEq(
            configTimelock.pendingInitialDiscountActionId(),
            actionId,
            "pending discount action id"
        );
    }

    // queueSetInitialDiscount
    // given a discount update is already pending
    //  when queueing another discount update
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_ConflictingActionPending
    function test_givenPendingDiscountUpdate_reverts() public {
        uint64 pendingActionId = _queueSetInitialDiscount(1e16);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityConfigTimelock
                    .IYieldRepurchaseFacilityConfigTimelock_ConflictingActionPending
                    .selector,
                IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
                pendingActionId
            )
        );
        configTimelock.queueSetInitialDiscount(2e16);
    }

    // queueSetInitialDiscount
    // given a yield buyback share update is pending
    //  when queueing a discount update
    //   then it queues (the parameter slots are independent)
    function test_givenPendingShareUpdate_queuesAction() public {
        _registerBackingAsset(yieldRepo, 0);
        uint64 shareActionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);

        uint64 discountActionId = _queueSetInitialDiscount(1e16);

        assertEq(discountActionId, shareActionId + 1, "discount action id");
    }

    // queueSetInitialDiscount
    // given the pending discount update has been executed
    //  when queueing a new discount update
    //   then it queues (execution releases the pending slot)
    function test_givenPendingDiscountExecuted_allowsNewQueue() public {
        uint64 executedActionId = _queueSetInitialDiscount(1e16);
        _warpToExecutable(configTimelock, executedActionId);
        configTimelock.executeQueuedAction(executedActionId);

        uint64 actionId = _queueSetInitialDiscount(2e16);

        assertEq(actionId, executedActionId + 1, "action id");
        assertEq(
            configTimelock.pendingInitialDiscountActionId(),
            actionId,
            "pending discount action id"
        );
    }

    // queueSetInitialDiscount
    // given the pending discount update has been cancelled
    //  when queueing a new discount update
    //   then it queues (cancellation releases the pending slot)
    function test_givenPendingDiscountCancelled_allowsNewQueue() public {
        uint64 cancelledActionId = _queueSetInitialDiscount(1e16);
        vm.prank(guardian);
        configTimelock.cancelQueuedAction(cancelledActionId);

        uint64 actionId = _queueSetInitialDiscount(2e16);

        assertEq(actionId, cancelledActionId + 1, "action id");
    }

    // queueSetInitialDiscount
    // given a queued discount update
    //  when any caller executes at any timestamp within the execution window
    //   then the facility discount is updated and InitialDiscountSet is emitted
    function test_givenDelayElapsed_executesAction(uint48 elapsed_) public {
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueSetInitialDiscount(1e16);
        elapsed_ = uint48(
            bound(
                elapsed_,
                configTimelockDelay,
                configTimelockDelay + configTimelock.EXECUTION_WINDOW()
            )
        );
        vm.warp(queuedAt + elapsed_);

        vm.expectEmit(false, false, false, true, address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.InitialDiscountSet(1e16);
        configTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 1e16, "discount applied");
    }

    // queueSetInitialDiscount
    // given the discount was changed directly by the admin after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_PreStateChanged
    function test_givenDiscountChangedAfterQueue_revertsAsStale() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        vm.prank(guardian);
        yieldRepo.setInitialDiscount(5e16);
        _warpToExecutable(configTimelock, actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityConfigTimelock
                    .IYieldRepurchaseFacilityConfigTimelock_PreStateChanged
                    .selector,
                actionId,
                uint256(0),
                keccak256(abi.encode(uint256(0))),
                keccak256(abi.encode(uint256(5e16)))
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), 5e16, "admin value preserved");
    }

    // queueSetInitialDiscount
    // given a facility restart (`enable`) replaced the discount after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_PreStateChanged
    function test_givenFacilityRestartChangesDiscountAfterQueue_revertsAsStale() public {
        uint64 actionId = _queueSetInitialDiscount(1e16);
        // The admin restart seeds the base-configured 3% discount through `_beforeEnable`.
        _enableFacility();
        _warpToExecutable(configTimelock, actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityConfigTimelock
                    .IYieldRepurchaseFacilityConfigTimelock_PreStateChanged
                    .selector,
                actionId,
                uint256(0),
                keccak256(abi.encode(uint256(0))),
                keccak256(abi.encode(initialDiscount))
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.initialDiscount(), initialDiscount, "restart value preserved");
    }
}
