// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYRFTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYRFTimelock.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {YRFTimelock} from "src/policies/YieldRepurchaseFacility/YRFTimelock.sol";
import {YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {YRFTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YRFTimelock/YRFTimelockTestBase.sol";

contract YRFTimelockTests_QueueEnableAsset is YRFTimelockTestBase {
    // queueEnableAsset
    // given the caller does not hold the yrf_admin role
    //  when queueing an asset enable
    //   then it reverts with ROLES_RequireRole(yrf_admin)
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != yrfAdmin);
        address vault = _registerDisabledAsset();

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        yrfTimelock.queueEnableAsset(vault);
    }

    // queueEnableAsset
    // given the timelock policy is disabled
    //  when queueing an asset enable
    //   then it reverts with NotEnabled and no action id is consumed
    function test_givenTimelockDisabled_reverts() public {
        address vault = _registerDisabledAsset();
        vm.prank(guardian);
        yrfTimelock.disable("");

        vm.prank(yrfAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        yrfTimelock.queueEnableAsset(vault);

        assertEq(yrfTimelock.nextActionId(), 1, "next action id");
    }

    // queueEnableAsset
    // given the facility slot has not been set
    //  when queueing an asset enable
    //   then it reverts with IYRFTimelock_FacilityNotSet
    function test_givenFacilityNotSet_reverts() public {
        YRFTimelock unwired = _deployUnwiredTimelock();

        vm.prank(yrfAdmin);
        vm.expectRevert(IYRFTimelock.IYRFTimelock_FacilityNotSet.selector);
        unwired.queueEnableAsset(address(sReserve));
    }

    // queueEnableAsset
    // given the vault is not registered in the facility
    //  when queueing an asset enable
    //   then it reverts with IYieldRepurchaseFacilityV2_AssetNotRegistered
    function test_givenUnregisteredVault_reverts() public {
        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered.selector,
                address(sReserve)
            )
        );
        yrfTimelock.queueEnableAsset(address(sReserve));
    }

    // queueEnableAsset
    // given the asset is already enabled
    //  when queueing an asset enable
    //   then it reverts with IYieldRepurchaseFacilityV2_AssetEnabled
    function test_givenAssetAlreadyEnabled_reverts() public {
        address vault = _registerSecondaryAsset(yieldRepo, "secondary", 0);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetEnabled.selector
        );
        yrfTimelock.queueEnableAsset(vault);
    }

    // queueEnableAsset
    // given the asset is disabled
    //  when the yrf_admin queues the enable
    //   then the action is stored with the queue events and timelock timestamps
    function test_givenYrfAdminCaller_whenAssetDisabled_queuesAction() public {
        address vault = _registerDisabledAsset();
        uint256 queuedAt = vm.getBlockTimestamp();
        ITimelockBatchQueue.BatchAction[] memory actions = _singleAction(
            address(yieldRepo),
            IYieldRepurchaseFacilityV2.enableAsset.selector,
            abi.encode(vault)
        );

        _expectActionQueued(yrfTimelock, 1, yrfAdmin, actions);
        uint64 actionId = _queueEnableAsset(vault);

        assertEq(actionId, 1, "action id");
        _assertQueuedSingleAction(yrfTimelock, actionId, queuedAt, actions[0]);
    }

    // queueEnableAsset
    // given a queued asset enable
    //  when any caller executes within the execution window
    //   then the asset is enabled, its next yield is zeroed, and the snapshots are refreshed
    function test_givenDelayElapsed_executesActionAndResetsYieldState(uint48 elapsed_) public {
        // The asset is registered with a stale next yield and zeroed snapshots, so both the
        // reset and the refresh performed by `enableAsset` are observable.
        address vault = _registerSecondaryAsset(yieldRepo, "secondary", 50e18);
        vm.prank(guardian);
        yieldRepo.disableAsset(vault);
        address assetReserve = yieldRepo.getAssetConfig(vault).reserve;
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueEnableAsset(vault);
        elapsed_ = uint48(
            bound(elapsed_, yrfTimelockDelay, yrfTimelockDelay + yrfTimelock.EXECUTION_WINDOW())
        );
        vm.warp(queuedAt + elapsed_);

        vm.expectEmit(true, false, false, true, address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.AssetEnabled(vault);
        vm.expectEmit(true, false, false, true, address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.NextYieldSet(assetReserve, 0);
        yrfTimelock.executeQueuedAction(actionId);

        IYieldRepurchaseFacilityV2.ReserveAsset memory config = yieldRepo.getAssetConfig(vault);
        assertTrue(config.isAssetEnabled, "asset enabled");
        assertEq(config.nextYield, 0, "next yield zeroed");
        // The empty mock vault redeems 1:1, replacing the zeroed registration snapshot.
        assertEq(config.lastConversionRate, 1e18, "conversion rate refreshed");
        assertEq(config.lastReserveBalance, 0, "reserve balance snapshot refreshed");
    }

    // queueEnableAsset
    // given the asset was enabled directly by the admin after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityV2_AssetEnabled (facility re-validation)
    function test_givenAssetEnabledAfterQueue_executionReverts() public {
        address vault = _registerDisabledAsset();
        uint64 actionId = _queueEnableAsset(vault);
        vm.prank(guardian);
        yieldRepo.enableAsset(vault);
        _warpToExecutable(yrfTimelock, actionId);

        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetEnabled.selector
        );
        yrfTimelock.executeQueuedAction(actionId);
    }

    // queueEnableAsset
    // given the vault was removed from the facility after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityV2_AssetNotRegistered
    function test_givenVaultRemovedAfterQueue_executionReverts() public {
        address vault = _registerDisabledAsset();
        uint64 actionId = _queueEnableAsset(vault);
        vm.prank(guardian);
        yieldRepo.removeAsset(vault);
        _warpToExecutable(yrfTimelock, actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered.selector,
                vault
            )
        );
        yrfTimelock.executeQueuedAction(actionId);
    }

    // queueEnableAsset
    // given two enable actions are queued for the same disabled asset (no pending slot)
    //  when both execute in order
    //   then the first succeeds and the second reverts with the facility's state-flip error
    function test_givenTwoPendingEnables_secondExecutionReverts() public {
        address vault = _registerDisabledAsset();
        uint64 firstActionId = _queueEnableAsset(vault);
        uint64 secondActionId = _queueEnableAsset(vault);
        _warpToExecutable(yrfTimelock, secondActionId);

        yrfTimelock.executeQueuedAction(firstActionId);
        assertTrue(yieldRepo.getAssetConfig(vault).isAssetEnabled, "asset enabled");

        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetEnabled.selector
        );
        yrfTimelock.executeQueuedAction(secondActionId);

        assertFalse(yrfTimelock.getQueuedAction(secondActionId).executed, "second not executed");
        // The stuck duplicate remains cancellable.
        vm.prank(guardian);
        yrfTimelock.cancelQueuedAction(secondActionId);
        assertTrue(yrfTimelock.getQueuedAction(secondActionId).cancelled, "second cancelled");
    }

    // ========== HELPERS ========== //

    /// @notice Registers a fresh non-backing asset and disables it.
    function _registerDisabledAsset() private returns (address vault) {
        vault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        vm.prank(guardian);
        yieldRepo.disableAsset(vault);
    }
}
