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

contract YieldRepurchaseFacilityConfigTimelockTests_QueueDisableAsset is
    YieldRepurchaseFacilityConfigTimelockTestBase
{
    // queueDisableAsset
    // given the caller does not hold the yrf_admin role
    //  when queueing an asset disable
    //   then it reverts with ROLES_RequireRole(yrf_admin)
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != yrfAdmin);
        address vault = _registerSecondaryAsset(yieldRepo, "secondary", 0);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.queueDisableAsset(vault);
    }

    // queueDisableAsset
    // given the timelock policy is disabled
    //  when queueing an asset disable
    //   then it reverts with NotEnabled and no action id is consumed
    function test_givenTimelockDisabled_reverts() public {
        address vault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        vm.prank(guardian);
        configTimelock.disable("");

        vm.prank(yrfAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.queueDisableAsset(vault);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueDisableAsset
    // given the facility slot has not been set
    //  when queueing an asset disable
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
    function test_givenFacilityNotSet_reverts() public {
        YieldRepurchaseFacilityConfigTimelock unwired = _deployUnwiredTimelock();

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityConfigTimelock
                .IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
                .selector
        );
        unwired.queueDisableAsset(address(sReserve));
    }

    // queueDisableAsset
    // given the vault is not registered in the facility
    //  when queueing an asset disable
    //   then it reverts with IYieldRepurchaseFacilityV2_AssetNotRegistered
    function test_givenUnregisteredVault_reverts() public {
        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered.selector,
                address(sReserve)
            )
        );
        configTimelock.queueDisableAsset(address(sReserve));
    }

    // queueDisableAsset
    // given the asset is already disabled
    //  when queueing an asset disable
    //   then it reverts with IYieldRepurchaseFacilityV2_AssetDisabled
    function test_givenAssetAlreadyDisabled_reverts() public {
        address vault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        vm.prank(guardian);
        yieldRepo.disableAsset(vault);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetDisabled.selector
        );
        configTimelock.queueDisableAsset(vault);
    }

    // queueDisableAsset
    // given the vault is the backing vault
    //  when queueing an asset disable
    //   then it reverts with IYieldRepurchaseFacilityV2_VaultIsBackingVault
    function test_givenVaultIsBackingVault_reverts() public {
        _registerBackingAsset(yieldRepo, 0);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_VaultIsBackingVault.selector
        );
        configTimelock.queueDisableAsset(address(sReserve));
    }

    // queueDisableAsset
    // given the asset is enabled and is not the backing vault
    //  when the yrf_admin queues the disable
    //   then the action is stored with the queue events and timelock timestamps
    function test_givenYrfAdminCaller_whenAssetEnabled_queuesAction() public {
        address vault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        uint256 queuedAt = vm.getBlockTimestamp();
        ITimelockBatchQueue.BatchAction[] memory actions = _singleAction(
            address(yieldRepo),
            IYieldRepurchaseFacilityV2.disableAsset.selector,
            abi.encode(vault)
        );

        _expectActionQueued(configTimelock, 1, yrfAdmin, actions);
        uint64 actionId = _queueDisableAsset(vault);

        assertEq(actionId, 1, "action id");
        _assertQueuedSingleAction(configTimelock, actionId, queuedAt, actions[0]);
    }

    // queueDisableAsset
    // given a queued asset disable
    //  when any caller executes within the execution window
    //   then the asset is disabled and AssetDisabled is emitted
    function test_givenDelayElapsed_executesAction(uint48 elapsed_) public {
        address vault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueDisableAsset(vault);
        elapsed_ = uint48(
            bound(
                elapsed_,
                configTimelockDelay,
                configTimelockDelay + configTimelock.EXECUTION_WINDOW()
            )
        );
        vm.warp(queuedAt + elapsed_);

        vm.expectEmit(true, false, false, true, address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.AssetDisabled(vault);
        configTimelock.executeQueuedAction(actionId);

        assertFalse(yieldRepo.getAssetConfig(vault).isAssetEnabled, "asset disabled");
    }

    // queueDisableAsset
    // given the asset was disabled directly by the admin after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityV2_AssetDisabled (facility re-validation)
    function test_givenAssetDisabledAfterQueue_executionReverts() public {
        address vault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        uint64 actionId = _queueDisableAsset(vault);
        vm.prank(guardian);
        yieldRepo.disableAsset(vault);
        _warpToExecutable(configTimelock, actionId);

        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetDisabled.selector
        );
        configTimelock.executeQueuedAction(actionId);
    }

    // queueDisableAsset
    // given the vault became the backing vault after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityV2_VaultIsBackingVault
    function test_givenVaultBecameBackingVaultAfterQueue_executionReverts() public {
        address vault = _registerSecondaryAsset(yieldRepo, "secondary", 0);
        uint64 actionId = _queueDisableAsset(vault);
        vm.prank(guardian);
        yieldRepo.setBackingVault(vault);
        _warpToExecutable(configTimelock, actionId);

        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_VaultIsBackingVault.selector
        );
        configTimelock.executeQueuedAction(actionId);
    }
}
