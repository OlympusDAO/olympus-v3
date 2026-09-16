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

contract YieldRepurchaseFacilityConfigTimelockTests_QueueBatch is
    YieldRepurchaseFacilityConfigTimelockTestBase
{
    // queueBatch
    // given the caller does not hold the yrf_admin role
    //  when queueing a valid batch
    //   then it reverts before validating sub-actions
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != yrfAdmin);
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.queueBatch(actions);
    }

    // queueBatch
    // given the caller holds only the admin role
    //  when queueing a valid batch
    //   then it reverts (yrf_admin is the sole queue proposer)
    function test_givenAdminCaller_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.queueBatch(actions);
    }

    // queueBatch
    // given the timelock policy is disabled
    //  when queueing a valid batch
    //   then it reverts with NotEnabled and no action id is consumed
    function test_givenTimelockDisabled_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        vm.prank(guardian);
        configTimelock.disable("");

        vm.prank(yrfAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given the facility slot has not been set
    //  when queueing a valid batch
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
    function test_givenFacilityNotSet_reverts() public {
        YieldRepurchaseFacilityConfigTimelock unwired = _deployUnwiredTimelock();
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityConfigTimelock
                .IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
                .selector
        );
        unwired.queueBatch(actions);
    }

    // queueBatch
    // given the batch is empty
    //  when queueing the batch
    //   then it reverts with ITimelockBatchQueue_BatchEmpty
    function test_givenBatchIsEmpty_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](0);

        vm.prank(yrfAdmin);
        vm.expectRevert(ITimelockBatchQueue.ITimelockBatchQueue_BatchEmpty.selector);
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given the batch exceeds the maximum batch size
    //  when queueing the batch
    //   then it reverts with ITimelockBatchQueue_BatchTooLarge
    function test_givenBatchTooLarge_reverts() public {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](
            16
        );

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_BatchTooLarge.selector,
                16,
                15
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given a valid mixed batch
    //  when the yrf_admin queues the batch
    //   then every sub-action is stored and the queue events are emitted in order
    function test_givenYrfAdminCaller_whenBatchIsValid_queuesBatch() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();

        _expectActionQueued(configTimelock, 1, yrfAdmin, actions);
        uint64 actionId = _queueBatch(actions);

        assertEq(actionId, 1, "action id");
        assertEq(
            configTimelock.getQueuedActionLength(actionId),
            actions.length,
            "sub-action count"
        );
    }

    // queueBatch
    // given a queued batch
    //  when reading getQueuedAction, getQueuedActionLength, and getQueuedSubAction
    //   then the stored sub-actions and metadata are returned
    function test_givenQueuedBatch_exposesSubActionsThroughViews() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueBatch(actions);

        ITimelockBatchQueue.QueuedAction memory action = configTimelock.getQueuedAction(actionId);
        assertEq(action.proposer, yrfAdmin, "proposer");
        assertEq(action.queuedAt, queuedAt, "queuedAt");
        assertEq(action.actions.length, actions.length, "stored sub-action count");
        assertEq(
            configTimelock.getQueuedActionLength(actionId),
            actions.length,
            "sub-action count"
        );
        for (uint256 i = 0; i < actions.length; ++i) {
            (address target, bytes4 selector, bytes memory payload) = configTimelock
                .getQueuedSubAction(actionId, i);
            assertEq(target, actions[i].target, "target");
            assertEq(selector, actions[i].selector, "selector");
            assertEq(payload, actions[i].payload, "payload");
        }
    }

    // queueBatch
    // given a queued batch
    //  when reading a sub-action index beyond the stored length
    //   then it reverts with ITimelockBatchQueue_SubActionIndexOutOfBounds
    function test_givenSubActionIndexOutOfBounds_reverts() public {
        uint64 actionId = _queueBatch(_mixedBatch());

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_SubActionIndexOutOfBounds.selector,
                actionId,
                2,
                2
            )
        );
        configTimelock.getQueuedSubAction(actionId, 2);
    }

    // queueBatch
    // given one sub-action targets an address other than the facility
    //  when queueing the batch
    //   then the whole batch reverts and no action id is consumed
    function test_givenSubActionWrongTarget_revertsWholeQueue() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        actions[1].target = makeAddr("wrongTarget");

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                actions[1].target,
                actions[1].selector
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given one sub-action uses an unsupported selector
    //  when queueing the batch
    //   then the whole batch reverts and no action id is consumed
    function test_givenSubActionUnsupportedSelector_revertsWholeQueue() public {
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        // The inclusion of a Clearinghouse is admin-only and deliberately not reachable
        // through the timelock queue.
        actions[1].selector = IYieldRepurchaseFacilityV2.includeClearinghouse.selector;
        actions[1].payload = abi.encode(address(clearinghouse));

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(yieldRepo),
                actions[1].selector
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given one sub-action fails its selector-specific validation
    //  when queueing the batch
    //   then the whole batch reverts and no action id is consumed
    function test_givenSubActionConfigInvalid_revertsWholeQueue() public {
        _registerBackingAsset(yieldRepo, 0);
        ITimelockBatchQueue.BatchAction[] memory actions = _mixedBatch();
        actions[1] = _facilityAction(
            IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
            abi.encode(address(sReserve), uint256(1e18 + 1))
        );

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh.selector
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
        // The pending slot taken by the earlier discount sub-action is rolled back.
        assertEq(configTimelock.pendingInitialDiscountActionId(), 0, "no pending slot leaked");
    }

    // queueBatch
    // given a setYieldBuybackShare payload of the wrong length
    //  when queueing the batch
    //   then it reverts with ITimelockBatchQueue_ActionInvalid(address(0), selector)
    function test_givenMalformedYieldBuybackSharePayload_reverts() public {
        _expectMalformedPayloadRevert(
            IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
            abi.encode(address(sReserve))
        );
    }

    // queueBatch
    // given a setInitialDiscount payload of the wrong length
    //  when queueing the batch
    //   then it reverts with ITimelockBatchQueue_ActionInvalid(address(0), selector)
    function test_givenMalformedInitialDiscountPayload_reverts() public {
        _expectMalformedPayloadRevert(
            IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
            abi.encode(uint256(1e16), uint256(1))
        );
    }

    // queueBatch
    // given an enableAsset payload of the wrong length
    //  when queueing the batch
    //   then it reverts with ITimelockBatchQueue_ActionInvalid(address(0), selector)
    function test_givenMalformedEnableAssetPayload_reverts() public {
        _expectMalformedPayloadRevert(
            IYieldRepurchaseFacilityV2.enableAsset.selector,
            abi.encode(address(sReserve), uint256(1))
        );
    }

    // queueBatch
    // given a disableAsset payload of the wrong length
    //  when queueing the batch
    //   then it reverts with ITimelockBatchQueue_ActionInvalid(address(0), selector)
    function test_givenMalformedDisableAssetPayload_reverts() public {
        _expectMalformedPayloadRevert(IYieldRepurchaseFacilityV2.disableAsset.selector, "");
    }

    // queueBatch
    // given an excludeClearinghouse payload of the wrong length
    //  when queueing the batch
    //   then it reverts with ITimelockBatchQueue_ActionInvalid(address(0), selector)
    function test_givenMalformedExcludeClearinghousePayload_reverts() public {
        _expectMalformedPayloadRevert(
            IYieldRepurchaseFacilityV2.excludeClearinghouse.selector,
            abi.encode(address(clearinghouse), address(clearinghouse))
        );
    }

    // queueBatch
    // given an increaseClearinghouseOffset payload of the wrong length
    //  when queueing the batch
    //   then it reverts with ITimelockBatchQueue_ActionInvalid(address(0), selector)
    function test_givenMalformedIncreaseClearinghouseOffsetPayload_reverts() public {
        _expectMalformedPayloadRevert(
            IYieldRepurchaseFacilityV2.increaseClearinghouseOffset.selector,
            abi.encode(address(clearinghouse))
        );
    }

    // queueBatch
    // given a decreaseNextYield payload of the wrong length
    //  when queueing the batch
    //   then it reverts with ITimelockBatchQueue_ActionInvalid(address(0), selector)
    function test_givenMalformedDecreaseNextYieldPayload_reverts() public {
        _expectMalformedPayloadRevert(
            IYieldRepurchaseFacilityV2.decreaseNextYield.selector,
            abi.encode(address(sReserve), uint256(1))
        );
    }

    // queueBatch
    // given an address payload word with dirty upper bits
    //  when queueing the batch
    //   then abi.decode rejects the non-canonical encoding and the queue reverts
    function test_givenDirtyAddressPayload_reverts() public {
        bytes32 dirtyWord = bytes32(uint256(uint160(address(sReserve))) | (uint256(1) << 200));
        ITimelockBatchQueue.BatchAction[] memory actions = _singleAction(
            address(yieldRepo),
            IYieldRepurchaseFacilityV2.enableAsset.selector,
            abi.encodePacked(dirtyWord)
        );

        vm.prank(yrfAdmin);
        vm.expectRevert();
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueBatch
    // given two sub-actions taking the same pending parameter slot in one batch
    //  when queueing the batch
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_ConflictingActionPending
    function test_givenConflictingLockedSubActionsInBatch_reverts() public {
        _registerBackingAsset(yieldRepo, 0);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _facilityAction(
            IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
            abi.encode(address(sReserve), uint256(5e17))
        );
        actions[1] = _facilityAction(
            IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
            abi.encode(address(sReserve), uint256(6e17))
        );

        // The earlier sub-action of the batch being queued already holds the slot under the
        // action id being assigned.
        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityConfigTimelock
                    .IYieldRepurchaseFacilityConfigTimelock_ConflictingActionPending
                    .selector,
                IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
                uint64(1)
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
        assertEq(
            configTimelock.pendingYieldBuybackShareActionId(address(sReserve)),
            0,
            "no pending slot leaked"
        );
    }

    // queueBatch
    // given locked-parameter sub-actions for different parameters in one batch
    //  when queueing the batch
    //   then it queues and both pending slots point at the batch action id
    function test_givenLockedSubActionsForDifferentParams_queuesBatch() public {
        _registerBackingAsset(yieldRepo, 0);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _facilityAction(
            IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
            abi.encode(address(sReserve), uint256(5e17))
        );
        actions[1] = _facilityAction(
            IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
            abi.encode(uint256(1e16))
        );

        uint64 actionId = _queueBatch(actions);

        assertEq(configTimelock.getQueuedActionLength(actionId), 2, "sub-action count");
        assertEq(
            configTimelock.pendingYieldBuybackShareActionId(address(sReserve)),
            actionId,
            "share slot held by batch"
        );
        assertEq(
            configTimelock.pendingInitialDiscountActionId(),
            actionId,
            "discount slot held by batch"
        );
    }

    // queueBatch
    // given share updates for different vaults in one batch (the pending slots are keyed
    //   per vault, not per selector)
    //  when queueing and executing the batch
    //   then it queues, each vault's slot points at the batch, and both updates apply
    function test_givenShareUpdatesForDifferentVaultsInBatch_queuesAndExecutes() public {
        _registerBackingAsset(yieldRepo, 0);
        address secondaryVault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _facilityAction(
            IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
            abi.encode(address(sReserve), uint256(5e17))
        );
        actions[1] = _facilityAction(
            IYieldRepurchaseFacilityV2.setYieldBuybackShare.selector,
            abi.encode(secondaryVault, uint256(6e17))
        );

        uint64 actionId = _queueBatch(actions);

        assertEq(
            configTimelock.pendingYieldBuybackShareActionId(address(sReserve)),
            actionId,
            "backing slot held by batch"
        );
        assertEq(
            configTimelock.pendingYieldBuybackShareActionId(secondaryVault),
            actionId,
            "secondary slot held by batch"
        );

        _warpToExecutable(configTimelock, actionId);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            yieldRepo.getAssetConfig(address(sReserve)).yieldBuybackShare,
            5e17,
            "backing share applied"
        );
        assertEq(
            yieldRepo.getAssetConfig(secondaryVault).yieldBuybackShare,
            6e17,
            "secondary share applied"
        );
        assertEq(
            configTimelock.pendingYieldBuybackShareActionId(address(sReserve)),
            0,
            "backing slot released"
        );
        assertEq(
            configTimelock.pendingYieldBuybackShareActionId(secondaryVault),
            0,
            "secondary slot released"
        );
    }

    // queueBatch
    // given a later flip sub-action depends on an earlier sub-action's effect
    //  when queueing the batch (validation is against live state, no batch-local projection)
    //   then it reverts at queue time with the facility's state-flip error
    function test_givenDependentFlipSubActions_revertsAtQueue() public {
        address vault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _facilityAction(
            IYieldRepurchaseFacilityV2.disableAsset.selector,
            abi.encode(vault)
        );
        actions[1] = _facilityAction(
            IYieldRepurchaseFacilityV2.enableAsset.selector,
            abi.encode(vault)
        );

        // The re-enable is validated against the live (still enabled) state, so the
        // disable-then-enable batch cannot be queued.
        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetEnabled.selector
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // ========== HELPERS ========== //

    /// @notice A two-selector batch that requires no facility state preparation.
    function _mixedBatch() private view returns (ITimelockBatchQueue.BatchAction[] memory actions) {
        actions = new ITimelockBatchQueue.BatchAction[](2);
        actions[0] = _facilityAction(
            IYieldRepurchaseFacilityV2.setInitialDiscount.selector,
            abi.encode(uint256(1e16))
        );
        actions[1] = _facilityAction(
            IYieldRepurchaseFacilityV2.increaseClearinghouseOffset.selector,
            abi.encode(address(clearinghouse), uint256(0))
        );
    }

    /// @notice Queues a length-1 batch with `payload_` and expects the payload-shape revert.
    function _expectMalformedPayloadRevert(bytes4 selector_, bytes memory payload_) private {
        ITimelockBatchQueue.BatchAction[] memory actions = _singleAction(
            address(yieldRepo),
            selector_,
            payload_
        );

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_ActionInvalid.selector,
                address(0),
                selector_
            )
        );
        configTimelock.queueBatch(actions);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }
}
