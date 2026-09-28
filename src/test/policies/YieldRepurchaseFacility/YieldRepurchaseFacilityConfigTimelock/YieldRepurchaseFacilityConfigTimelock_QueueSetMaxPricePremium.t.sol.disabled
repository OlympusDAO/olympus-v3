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

contract YieldRepurchaseFacilityConfigTimelockTests_QueueSetMaxPricePremium is
    YieldRepurchaseFacilityConfigTimelockTestBase
{
    // queueSetMaxPricePremium
    // given the caller does not hold the yrf_admin role
    //  when queueing a premium update
    //   then it reverts with ROLES_RequireRole(yrf_admin)
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != yrfAdmin);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.queueSetMaxPricePremium(1e16);
    }

    // queueSetMaxPricePremium
    // given the caller holds only the admin role
    //  when queueing a premium update
    //   then it reverts (yrf_admin is the sole queue proposer)
    function test_givenAdminCaller_reverts() public {
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.queueSetMaxPricePremium(1e16);
    }

    // queueSetMaxPricePremium
    // given the timelock policy is disabled
    //  when queueing a premium update
    //   then it reverts with NotEnabled and no action id is consumed
    function test_givenTimelockDisabled_reverts() public {
        vm.prank(guardian);
        configTimelock.disable("");

        vm.prank(yrfAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.queueSetMaxPricePremium(1e16);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueSetMaxPricePremium
    // given the facility slot has not been set
    //  when queueing a premium update
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
    function test_givenFacilityNotSet_reverts() public {
        YieldRepurchaseFacilityConfigTimelock unwired = _deployUnwiredTimelock();

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityConfigTimelock
                .IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
                .selector
        );
        unwired.queueSetMaxPricePremium(1e16);
    }

    // queueSetMaxPricePremium
    // given the premium is exactly the upper bound (10e18)
    //  when queueing the premium
    //   then the action is queued (inclusive bound)
    function test_givenPremiumAtUpperBound_queuesAction() public {
        vm.prank(yrfAdmin);
        configTimelock.queueSetMaxPricePremium(10e18);

        assertEq(
            configTimelock.pendingMaxPricePremiumActionId(),
            1,
            "the premium at the upper bound was not queued"
        );
    }

    // queueSetMaxPricePremium
    // given the premium is one above the upper bound (10e18)
    //  when queueing the premium
    //   then it reverts with IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh
    function test_givenPremiumOneAboveUpperBound_reverts() public {
        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh.selector
        );
        configTimelock.queueSetMaxPricePremium(10e18 + 1);
    }

    // queueSetMaxPricePremium
    // given the premium is above the upper bound (10e18)
    //  when queueing any such premium
    //   then it reverts with IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh
    function test_givenPremiumAboveUpperBound_reverts(uint256 premium_) public {
        premium_ = bound(premium_, 10e18 + 1, type(uint256).max);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh.selector
        );
        configTimelock.queueSetMaxPricePremium(premium_);
    }

    // queueSetMaxPricePremium
    // given any premium at or below the upper bound (10e18)
    //  when the yrf_admin queues the premium
    //   then the action is stored with the queue events and timelock timestamps
    function test_givenYrfAdminCaller_whenPremiumIsValid_queuesAction(uint256 premium_) public {
        premium_ = bound(premium_, 0, 10e18);
        uint256 queuedAt = vm.getBlockTimestamp();
        ITimelockBatchQueue.BatchAction[] memory actions = _singleAction(
            address(yieldRepo),
            IYieldRepurchaseFacilityV2.setMaxPricePremium.selector,
            abi.encode(premium_)
        );

        _expectActionQueued(configTimelock, 1, yrfAdmin, actions);
        uint64 actionId = _queueSetMaxPricePremium(premium_);

        assertEq(actionId, 1, "action id");
        _assertQueuedSingleAction(configTimelock, actionId, queuedAt, actions[0]);
    }

    // queueSetMaxPricePremium
    // given a premium update is queued
    //  when reading pendingMaxPricePremiumActionId
    //   then it returns the queued action id
    function test_givenQueuedAction_recordsPendingSlot() public {
        uint64 actionId = _queueSetMaxPricePremium(1e16);

        assertEq(
            configTimelock.pendingMaxPricePremiumActionId(),
            actionId,
            "pending premium action id"
        );
    }

    // queueSetMaxPricePremium
    // given a premium update is already pending
    //  when queueing another premium update
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_ConflictingActionPending
    function test_givenPendingPremiumUpdate_reverts() public {
        uint64 pendingActionId = _queueSetMaxPricePremium(1e16);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityConfigTimelock
                    .IYieldRepurchaseFacilityConfigTimelock_ConflictingActionPending
                    .selector,
                IYieldRepurchaseFacilityV2.setMaxPricePremium.selector,
                pendingActionId
            )
        );
        configTimelock.queueSetMaxPricePremium(2e16);
    }

    // queueSetMaxPricePremium
    // given an initial discount update is pending
    //  when queueing a premium update
    //   then it queues (the parameter slots are independent)
    function test_givenPendingDiscountUpdate_queuesAction() public {
        uint64 discountActionId = _queueSetInitialDiscount(1e16);

        uint64 premiumActionId = _queueSetMaxPricePremium(1e16);

        assertEq(premiumActionId, discountActionId + 1, "premium action id");
        assertEq(
            configTimelock.pendingInitialDiscountActionId(),
            discountActionId,
            "pending discount action id"
        );
        assertEq(
            configTimelock.pendingMaxPricePremiumActionId(),
            premiumActionId,
            "pending premium action id"
        );
    }

    // queueSetMaxPricePremium
    // given the pending premium update has been executed
    //  when queueing a new premium update
    //   then it queues (execution releases the pending slot)
    function test_givenPendingPremiumExecuted_allowsNewQueue() public {
        uint64 executedActionId = _queueSetMaxPricePremium(1e16);
        _warpToExecutable(configTimelock, executedActionId);
        configTimelock.executeQueuedAction(executedActionId);

        uint64 actionId = _queueSetMaxPricePremium(2e16);

        assertEq(actionId, executedActionId + 1, "action id");
        assertEq(
            configTimelock.pendingMaxPricePremiumActionId(),
            actionId,
            "pending premium action id"
        );
    }

    // queueSetMaxPricePremium
    // given the pending premium update has been cancelled
    //  when queueing a new premium update
    //   then it queues (cancellation releases the pending slot)
    function test_givenPendingPremiumCancelled_allowsNewQueue() public {
        uint64 cancelledActionId = _queueSetMaxPricePremium(1e16);
        vm.prank(guardian);
        configTimelock.cancelQueuedAction(cancelledActionId);

        uint64 actionId = _queueSetMaxPricePremium(2e16);

        assertEq(actionId, cancelledActionId + 1, "action id");
    }

    // queueSetMaxPricePremium
    // given a queued premium update
    //  when any caller executes at any timestamp within the execution window
    //   then the facility premium is updated and MaxPricePremiumSet is emitted
    function test_givenDelayElapsed_executesAction(uint48 elapsed_) public {
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueSetMaxPricePremium(1e16);
        elapsed_ = uint48(
            bound(
                elapsed_,
                configTimelockDelay,
                configTimelockDelay + configTimelock.EXECUTION_WINDOW()
            )
        );
        vm.warp(queuedAt + elapsed_);

        vm.expectEmit(false, false, false, true, address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.MaxPricePremiumSet(1e16);
        configTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.maxPricePremium(), 1e16, "premium applied");
    }

    // queueSetMaxPricePremium
    // given the premium was changed directly by the admin after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_PreStateChanged
    function test_givenPremiumChangedAfterQueue_revertsAsStale() public {
        uint64 actionId = _queueSetMaxPricePremium(1e16);
        vm.prank(guardian);
        yieldRepo.setMaxPricePremium(5e16);
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

        assertEq(yieldRepo.maxPricePremium(), 5e16, "admin value preserved");
    }

    // queueSetMaxPricePremium
    // given a facility restart (`enable`) replaced the premium after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_PreStateChanged
    function test_givenFacilityRestartChangesPremiumAfterQueue_revertsAsStale() public {
        uint64 actionId = _queueSetMaxPricePremium(1e16);
        // The admin restart seeds the base-configured 10% premium through `_beforeEnable`.
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
                keccak256(abi.encode(maxPricePremium))
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.maxPricePremium(), maxPricePremium, "restart value preserved");
    }
}
