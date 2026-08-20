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

contract YieldRepurchaseFacilityConfigTimelockTests_QueueSetYieldBuybackShare is
    YieldRepurchaseFacilityConfigTimelockTestBase
{
    // queueSetYieldBuybackShare
    // given the caller does not hold the yrf_admin role
    //  when queueing a share update
    //   then it reverts with ROLES_RequireRole(yrf_admin)
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != yrfAdmin);
        _registerBackingAsset(yieldRepo, 0);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.queueSetYieldBuybackShare(address(sReserve), 5e17);
    }

    // queueSetYieldBuybackShare
    // given the caller holds only the admin role
    //  when queueing a share update
    //   then it reverts (yrf_admin is the sole queue proposer)
    function test_givenAdminCaller_reverts() public {
        _registerBackingAsset(yieldRepo, 0);

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.queueSetYieldBuybackShare(address(sReserve), 5e17);
    }

    // queueSetYieldBuybackShare
    // given the timelock policy is disabled
    //  when queueing a share update
    //   then it reverts with NotEnabled and no action id is consumed
    function test_givenTimelockDisabled_reverts() public {
        _registerBackingAsset(yieldRepo, 0);
        vm.prank(guardian);
        configTimelock.disable("");

        vm.prank(yrfAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.queueSetYieldBuybackShare(address(sReserve), 5e17);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueSetYieldBuybackShare
    // given the facility slot has not been set
    //  when queueing a share update
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
    function test_givenFacilityNotSet_reverts() public {
        YieldRepurchaseFacilityConfigTimelock unwired = _deployUnwiredTimelock();

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityConfigTimelock
                .IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
                .selector
        );
        unwired.queueSetYieldBuybackShare(address(sReserve), 5e17);
    }

    // queueSetYieldBuybackShare
    // given the vault is not registered in the facility
    //  when queueing a share update
    //   then it reverts with IYieldRepurchaseFacilityV2_AssetNotRegistered
    function test_givenUnregisteredVault_reverts() public {
        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered.selector,
                address(sReserve)
            )
        );
        configTimelock.queueSetYieldBuybackShare(address(sReserve), 5e17);
    }

    // queueSetYieldBuybackShare
    // given the new share is above 100% (1e18)
    //  when queueing any such share
    //   then it reverts with IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh
    function test_givenShareAboveOneHundredPercent_reverts(uint256 newShare_) public {
        _registerBackingAsset(yieldRepo, 0);
        newShare_ = bound(newShare_, 1e18 + 1, type(uint256).max);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh.selector
        );
        configTimelock.queueSetYieldBuybackShare(address(sReserve), newShare_);
    }

    // queueSetYieldBuybackShare
    // given the new share is exactly 100% (1e18)
    //  when queueing the share
    //   then the action is queued (inclusive boundary)
    function test_givenShareAtOneHundredPercent_queuesAction() public {
        _registerBackingAsset(yieldRepo, 0);

        uint64 actionId = _queueSetYieldBuybackShare(address(sReserve), 1e18);

        assertEq(actionId, 1, "action id");
    }

    // queueSetYieldBuybackShare
    // given any share within [0, 1e18]
    //  when the yrf_admin queues the share
    //   then the action is stored with the queue events and timelock timestamps
    function test_givenYrfAdminCaller_whenShareIsValid_queuesAction(uint256 newShare_) public {
        _registerBackingAsset(yieldRepo, 0);
        newShare_ = bound(newShare_, 0, 1e18);
        uint256 queuedAt = vm.getBlockTimestamp();
        ITimelockBatchQueue.BatchAction[] memory actions = _singleAction(
            address(yieldRepo),
            IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
            abi.encode(address(sReserve), newShare_)
        );

        _expectActionQueued(configTimelock, 1, yrfAdmin, actions);
        uint64 actionId = _queueSetYieldBuybackShare(address(sReserve), newShare_);

        assertEq(actionId, 1, "action id");
        _assertQueuedSingleAction(configTimelock, actionId, queuedAt, actions[0]);
    }

    // queueSetYieldBuybackShare
    // given a share update is queued
    //  when reading pendingYieldBuybackShareActionId for the vault
    //   then it returns the queued action id
    function test_givenQueuedAction_recordsPendingSlot() public {
        _registerBackingAsset(yieldRepo, 0);

        uint64 actionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);

        assertEq(
            configTimelock.pendingYieldBuybackShareActionId(address(sReserve)),
            actionId,
            "pending share action id"
        );
    }

    // queueSetYieldBuybackShare
    // given a share update for the vault is already pending
    //  when queueing another share update for the same vault
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_ConflictingActionPending
    function test_givenPendingShareUpdateForSameVault_reverts() public {
        _registerBackingAsset(yieldRepo, 0);
        uint64 pendingActionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityConfigTimelock
                    .IYieldRepurchaseFacilityConfigTimelock_ConflictingActionPending
                    .selector,
                IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
                pendingActionId
            )
        );
        configTimelock.queueSetYieldBuybackShare(address(sReserve), 6e17);
    }

    // queueSetYieldBuybackShare
    // given a share update for another vault is pending
    //  when queueing a share update for this vault
    //   then it queues (the pending slots are per vault)
    function test_givenPendingShareUpdateForOtherVault_queuesAction() public {
        _registerBackingAsset(yieldRepo, 0);
        address secondaryVault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        uint64 backingActionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);

        uint64 secondaryActionId = _queueSetYieldBuybackShare(secondaryVault, 6e17);

        assertEq(
            configTimelock.pendingYieldBuybackShareActionId(address(sReserve)),
            backingActionId,
            "backing pending slot"
        );
        assertEq(
            configTimelock.pendingYieldBuybackShareActionId(secondaryVault),
            secondaryActionId,
            "secondary pending slot"
        );
    }

    // queueSetYieldBuybackShare
    // given an initial discount update is pending
    //  when queueing a share update
    //   then it queues (the parameter slots are independent)
    function test_givenPendingInitialDiscountUpdate_queuesAction() public {
        _registerBackingAsset(yieldRepo, 0);
        uint64 discountActionId = _queueSetInitialDiscount(1e16);

        uint64 shareActionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);

        assertEq(shareActionId, discountActionId + 1, "share action id");
    }

    // queueSetYieldBuybackShare
    // given the pending share update has been executed
    //  when queueing a new share update for the same vault
    //   then it queues (execution releases the pending slot)
    function test_givenPendingShareUpdateExecuted_allowsNewQueue() public {
        _registerBackingAsset(yieldRepo, 0);
        uint64 executedActionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);
        _warpToExecutable(configTimelock, executedActionId);
        configTimelock.executeQueuedAction(executedActionId);

        uint64 actionId = _queueSetYieldBuybackShare(address(sReserve), 6e17);

        assertEq(actionId, executedActionId + 1, "action id");
        assertEq(
            configTimelock.pendingYieldBuybackShareActionId(address(sReserve)),
            actionId,
            "pending share action id"
        );
    }

    // queueSetYieldBuybackShare
    // given the pending share update has been cancelled
    //  when queueing a new share update for the same vault
    //   then it queues (cancellation releases the pending slot)
    function test_givenPendingShareUpdateCancelled_allowsNewQueue() public {
        _registerBackingAsset(yieldRepo, 0);
        uint64 cancelledActionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);
        vm.prank(guardian);
        configTimelock.cancelQueuedAction(cancelledActionId);

        uint64 actionId = _queueSetYieldBuybackShare(address(sReserve), 6e17);

        assertEq(actionId, cancelledActionId + 1, "action id");
    }

    // queueSetYieldBuybackShare
    // given the pending share update has expired without execution
    //  when queueing a new share update for the same vault
    //   then it reverts until the expired holder is cancelled
    function test_givenPendingShareUpdateExpired_revertsUntilCancelled() public {
        _registerBackingAsset(yieldRepo, 0);
        uint64 expiredActionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);
        _warpPastExpiry(configTimelock, expiredActionId);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityConfigTimelock
                    .IYieldRepurchaseFacilityConfigTimelock_ConflictingActionPending
                    .selector,
                IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
                expiredActionId
            )
        );
        configTimelock.queueSetYieldBuybackShare(address(sReserve), 6e17);

        vm.prank(guardian);
        configTimelock.cancelQueuedAction(expiredActionId);
        assertEq(
            _queueSetYieldBuybackShare(address(sReserve), 6e17),
            expiredActionId + 1,
            "parameter can be queued again"
        );
    }

    // queueSetYieldBuybackShare
    // given a queued share update
    //  when any caller executes at any timestamp within the execution window
    //   then the facility share is updated and YieldBuybackShareSet is emitted
    function test_givenDelayElapsed_executesAction(uint48 elapsed_) public {
        _registerBackingAsset(yieldRepo, 0);
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);
        elapsed_ = uint48(
            bound(
                elapsed_,
                configTimelockDelay,
                configTimelockDelay + configTimelock.EXECUTION_WINDOW()
            )
        );
        vm.warp(queuedAt + elapsed_);

        vm.expectEmit(true, false, false, true, address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.YieldBuybackShareSet(address(sReserve), 5e17);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            yieldRepo.getAssetConfig(address(sReserve)).yieldBuybackShare,
            5e17,
            "share applied"
        );
    }

    // queueSetYieldBuybackShare
    // given the share was changed directly by the admin after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_PreStateChanged
    function test_givenShareChangedAfterQueue_revertsAsStale() public {
        _registerBackingAsset(yieldRepo, 0);
        uint64 actionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);
        vm.prank(guardian);
        yieldRepo.setYieldBuybackShare(address(sReserve), 9e17);
        _warpToExecutable(configTimelock, actionId);

        // The queue-time binding covers the registration-time share of 1e18.
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityConfigTimelock
                    .IYieldRepurchaseFacilityConfigTimelock_PreStateChanged
                    .selector,
                actionId,
                uint256(0),
                keccak256(abi.encode(address(sReserve), uint256(1e18))),
                keccak256(abi.encode(address(sReserve), uint256(9e17)))
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            yieldRepo.getAssetConfig(address(sReserve)).yieldBuybackShare,
            9e17,
            "admin value preserved"
        );
    }

    // queueSetYieldBuybackShare
    // given the share was changed and then restored to the queue-time value
    //  when the queued action executes
    //   then it executes (the binding is value-based)
    function test_givenShareChangedAndRestoredAfterQueue_executesAction() public {
        _registerBackingAsset(yieldRepo, 0);
        uint64 actionId = _queueSetYieldBuybackShare(address(sReserve), 5e17);
        vm.startPrank(guardian);
        yieldRepo.setYieldBuybackShare(address(sReserve), 9e17);
        yieldRepo.setYieldBuybackShare(address(sReserve), 1e18);
        vm.stopPrank();
        _warpToExecutable(configTimelock, actionId);

        configTimelock.executeQueuedAction(actionId);

        assertEq(
            yieldRepo.getAssetConfig(address(sReserve)).yieldBuybackShare,
            5e17,
            "share applied"
        );
    }

    // queueSetYieldBuybackShare
    // given the asset was disabled after the queue
    //  when the queued action executes
    //   then it executes (the binding covers only the share, and the facility setter does
    //   not require an enabled asset)
    function test_givenAssetDisabledAfterQueue_executesAction() public {
        address secondaryVault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        uint64 actionId = _queueSetYieldBuybackShare(secondaryVault, 5e17);
        vm.prank(guardian);
        yieldRepo.disableAsset(secondaryVault);
        _warpToExecutable(configTimelock, actionId);

        configTimelock.executeQueuedAction(actionId);

        IYieldRepurchaseFacilityV2.ReserveAsset memory config = yieldRepo.getAssetConfig(
            secondaryVault
        );
        assertEq(config.yieldBuybackShare, 5e17, "share applied");
        assertFalse(config.isAssetEnabled, "asset still disabled");
    }

    // queueSetYieldBuybackShare
    // given the vault was removed from the facility after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityV2_AssetNotRegistered
    function test_givenVaultRemovedAfterQueue_executionReverts() public {
        address secondaryVault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        uint64 actionId = _queueSetYieldBuybackShare(secondaryVault, 5e17);
        vm.startPrank(guardian);
        yieldRepo.disableAsset(secondaryVault);
        yieldRepo.removeAsset(secondaryVault);
        vm.stopPrank();
        _warpToExecutable(configTimelock, actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered.selector,
                secondaryVault
            )
        );
        configTimelock.executeQueuedAction(actionId);
    }
}
