// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueSetAssetOriginationsEnabledTest is
    BurnerLoansConfigTimelockTest
{
    event AssetOriginationsSet(address indexed asset, bool enabled);

    function _queueOriginationsEnabled(
        address asset_,
        bool enabled_
    ) internal returns (uint64 actionId) {
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(
            IBurnerLoansConfig.setAssetOriginationsEnabled.selector,
            abi.encode(asset_, enabled_)
        );
        return configTimelock.queueBatch(actions);
    }

    // queueSetAssetOriginationsEnabled
    // given caller has neither admin nor burner_loans_admin
    //  when an origination transition is queued
    //   then it reverts
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != burnerLoansAdmin);

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BURNER_LOANS_ADMIN_ROLE)
        );
        _queueOriginationsEnabled(address(usds), false);
    }

    // queueSetAssetOriginationsEnabled
    // given the asset is not configured
    //  when a transition is queued
    //   then it reverts
    function test_givenUnconfiguredAsset_reverts(address asset_) public {
        vm.assume(asset_ != address(usds));

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        _queueOriginationsEnabled(asset_, false);
    }

    // queueSetAssetOriginationsEnabled
    // given caller has burner_loans_admin
    //  when disabling originations is queued and executed
    //   then the config timelock applies the transition
    function test_givenBurnerLoansAdmin_queuesAndExecutesDisable() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = _queueOriginationsEnabled(address(usds), false);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetOriginationsSet(address(usds), false);
        _expectSingleActionExecuted(
            actionId,
            IBurnerLoansConfig.setAssetOriginationsEnabled.selector,
            address(this)
        );
        configTimelock.executeQueuedAction(actionId);

        assertFalse(
            burnerLoansConfig.getAssetConfig(address(usds)).originationsEnabled,
            "originations disabled"
        );
    }

    // queueSetAssetOriginationsEnabled
    // given caller has burner_loans_admin and originations are disabled
    //  when enabling originations is queued and executed
    //   then the config timelock applies the transition
    function test_givenBurnerLoansAdmin_queuesAndExecutesEnable() public {
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.prank(burnerLoansAdmin);
        uint64 actionId = _queueOriginationsEnabled(address(usds), true);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetOriginationsSet(address(usds), true);
        configTimelock.executeQueuedAction(actionId);

        assertTrue(
            burnerLoansConfig.getAssetConfig(address(usds)).originationsEnabled,
            "originations enabled"
        );
    }

    // queueSetAssetOriginationsEnabled
    // given admin changes the origination state after the action is queued
    //  when the queued transition is executed
    //   then the action is stale
    function test_givenOriginationStateChangedAfterQueue_reverts() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = _queueOriginationsEnabled(address(usds), false);
        bytes32 expectedHash = keccak256(
            abi.encode(address(usds), burnerLoansConfig.getAssetConfig(address(usds)))
        );

        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        bytes32 currentHash = keccak256(
            abi.encode(address(usds), burnerLoansConfig.getAssetConfig(address(usds)))
        );
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfigTimelock.BurnerLoansConfigTimelock_ConfigStateChanged.selector,
                actionId,
                0,
                expectedHash,
                currentHash
            )
        );
        configTimelock.executeQueuedAction(actionId);
    }
}
