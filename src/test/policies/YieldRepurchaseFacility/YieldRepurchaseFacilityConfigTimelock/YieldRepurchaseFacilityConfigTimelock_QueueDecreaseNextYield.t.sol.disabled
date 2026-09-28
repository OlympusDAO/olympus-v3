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

contract YieldRepurchaseFacilityConfigTimelockTests_QueueDecreaseNextYield is
    YieldRepurchaseFacilityConfigTimelockTestBase
{
    uint256 internal constant _STORED_NEXT_YIELD = 100e18;

    // queueDecreaseNextYield
    // given the caller does not hold the yrf_admin role
    //  when queueing a next-yield correction
    //   then it reverts with ROLES_RequireRole(yrf_admin)
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != yrfAdmin);
        _registerBackingAsset(yieldRepo, _STORED_NEXT_YIELD);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        configTimelock.queueDecreaseNextYield(address(sReserve), _STORED_NEXT_YIELD, 40e18);
    }

    // queueDecreaseNextYield
    // given the timelock policy is disabled
    //  when queueing a next-yield correction
    //   then it reverts with NotEnabled and no action id is consumed
    function test_givenTimelockDisabled_reverts() public {
        _registerBackingAsset(yieldRepo, _STORED_NEXT_YIELD);
        vm.prank(guardian);
        configTimelock.disable("");

        vm.prank(yrfAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.queueDecreaseNextYield(address(sReserve), _STORED_NEXT_YIELD, 40e18);

        assertEq(configTimelock.nextActionId(), 1, "next action id");
    }

    // queueDecreaseNextYield
    // given the facility slot has not been set
    //  when queueing a next-yield correction
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
    function test_givenFacilityNotSet_reverts() public {
        YieldRepurchaseFacilityConfigTimelock unwired = _deployUnwiredTimelock();

        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityConfigTimelock
                .IYieldRepurchaseFacilityConfigTimelock_FacilityNotSet
                .selector
        );
        unwired.queueDecreaseNextYield(address(sReserve), _STORED_NEXT_YIELD, 40e18);
    }

    // queueDecreaseNextYield
    // given the vault is not registered in the facility
    //  when queueing a next-yield correction
    //   then it reverts with IYieldRepurchaseFacilityV2_AssetNotRegistered
    function test_givenUnregisteredVault_reverts() public {
        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetNotRegistered.selector,
                address(sReserve)
            )
        );
        configTimelock.queueDecreaseNextYield(address(sReserve), _STORED_NEXT_YIELD, 40e18);
    }

    // queueDecreaseNextYield
    // given the expected next yield does not match the stored value
    //  when queueing any such correction
    //   then it reverts with IYieldRepurchaseFacilityV2_NextYieldMismatch
    function test_givenExpectedNextYieldMismatch_reverts(uint256 expectedNextYield_) public {
        vm.assume(expectedNextYield_ != _STORED_NEXT_YIELD);
        _registerBackingAsset(yieldRepo, _STORED_NEXT_YIELD);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_NextYieldMismatch.selector,
                address(sReserve),
                expectedNextYield_,
                _STORED_NEXT_YIELD
            )
        );
        configTimelock.queueDecreaseNextYield(address(sReserve), expectedNextYield_, 0);
    }

    // queueDecreaseNextYield
    // given the new next yield equals the stored value
    //  when queueing the correction
    //   then it reverts with IYieldRepurchaseFacilityV2_NextYieldNotDecreased (exclusive bound)
    function test_givenNewNextYieldEqualToStored_reverts() public {
        _registerBackingAsset(yieldRepo, _STORED_NEXT_YIELD);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_NextYieldNotDecreased
                    .selector,
                address(sReserve),
                _STORED_NEXT_YIELD,
                _STORED_NEXT_YIELD
            )
        );
        configTimelock.queueDecreaseNextYield(
            address(sReserve),
            _STORED_NEXT_YIELD,
            _STORED_NEXT_YIELD
        );
    }

    // queueDecreaseNextYield
    // given the new next yield is above the stored value
    //  when queueing any such correction
    //   then it reverts with IYieldRepurchaseFacilityV2_NextYieldNotDecreased
    function test_givenNewNextYieldAboveStored_reverts(uint256 newNextYield_) public {
        _registerBackingAsset(yieldRepo, _STORED_NEXT_YIELD);
        newNextYield_ = bound(newNextYield_, _STORED_NEXT_YIELD + 1, type(uint256).max);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_NextYieldNotDecreased
                    .selector,
                address(sReserve),
                newNextYield_,
                _STORED_NEXT_YIELD
            )
        );
        configTimelock.queueDecreaseNextYield(address(sReserve), _STORED_NEXT_YIELD, newNextYield_);
    }

    // queueDecreaseNextYield
    // given any new next yield below the stored value
    //  when the yrf_admin queues the correction
    //   then the action is stored with the queue events and timelock timestamps
    function test_givenYrfAdminCaller_whenDecreaseIsValid_queuesAction(
        uint256 newNextYield_
    ) public {
        _registerBackingAsset(yieldRepo, _STORED_NEXT_YIELD);
        newNextYield_ = bound(newNextYield_, 0, _STORED_NEXT_YIELD - 1);
        uint256 queuedAt = vm.getBlockTimestamp();
        ITimelockBatchQueue.BatchAction[] memory actions = _singleAction(
            address(yieldRepo),
            IYieldRepurchaseFacilityV2.decreaseNextYield.selector,
            abi.encode(address(sReserve), _STORED_NEXT_YIELD, newNextYield_)
        );

        _expectActionQueued(configTimelock, 1, yrfAdmin, actions);
        uint64 actionId = _queueDecreaseNextYield(
            address(sReserve),
            _STORED_NEXT_YIELD,
            newNextYield_
        );

        assertEq(actionId, 1, "action id");
        _assertQueuedSingleAction(configTimelock, actionId, queuedAt, actions[0]);
    }

    // queueDecreaseNextYield
    // given a correction to zero
    //  when queueing the correction
    //   then the action is queued (inclusive lower boundary)
    function test_givenZeroNewNextYield_queuesAction() public {
        _registerBackingAsset(yieldRepo, _STORED_NEXT_YIELD);

        uint64 actionId = _queueDecreaseNextYield(address(sReserve), _STORED_NEXT_YIELD, 0);

        assertEq(actionId, 1, "action id");
    }

    // queueDecreaseNextYield
    // given a queued correction
    //  when any caller executes at any timestamp within the execution window
    //   then the stored next yield is decreased and NextYieldSet is emitted
    function test_givenDelayElapsed_executesAction(uint48 elapsed_) public {
        _registerBackingAsset(yieldRepo, _STORED_NEXT_YIELD);
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueDecreaseNextYield(address(sReserve), _STORED_NEXT_YIELD, 40e18);
        elapsed_ = uint48(
            bound(
                elapsed_,
                configTimelockDelay,
                configTimelockDelay + configTimelock.EXECUTION_WINDOW()
            )
        );
        vm.warp(queuedAt + elapsed_);

        vm.expectEmit(true, false, false, true, address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.NextYieldSet(address(reserve), 40e18);
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            yieldRepo.getAssetConfig(address(sReserve)).nextYield,
            40e18,
            "next yield decreased"
        );
    }

    // queueDecreaseNextYield
    // given the stored next yield was replaced (weekly reset or direct correction) after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityV2_NextYieldMismatch (compare-and-set)
    function test_givenNextYieldChangedAfterQueue_executionReverts() public {
        _registerBackingAsset(yieldRepo, _STORED_NEXT_YIELD);
        uint64 actionId = _queueDecreaseNextYield(address(sReserve), _STORED_NEXT_YIELD, 40e18);
        // A direct admin correction replaces the stored value the queued action targets.
        vm.prank(guardian);
        yieldRepo.decreaseNextYield(address(sReserve), _STORED_NEXT_YIELD, 70e18);
        _warpToExecutable(configTimelock, actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_NextYieldMismatch.selector,
                address(sReserve),
                _STORED_NEXT_YIELD,
                70e18
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertEq(
            yieldRepo.getAssetConfig(address(sReserve)).nextYield,
            70e18,
            "direct correction preserved"
        );
    }

    // queueDecreaseNextYield
    // given two corrections queued against the same stored value
    //  when both execute in order
    //   then the first applies and the second reverts on the compare-and-set
    function test_givenTwoPendingDecreases_secondExecutionReverts() public {
        _registerBackingAsset(yieldRepo, _STORED_NEXT_YIELD);
        uint64 firstActionId = _queueDecreaseNextYield(
            address(sReserve),
            _STORED_NEXT_YIELD,
            40e18
        );
        uint64 secondActionId = _queueDecreaseNextYield(
            address(sReserve),
            _STORED_NEXT_YIELD,
            30e18
        );
        _warpToExecutable(configTimelock, secondActionId);

        configTimelock.executeQueuedAction(firstActionId);
        assertEq(
            yieldRepo.getAssetConfig(address(sReserve)).nextYield,
            40e18,
            "first correction applied"
        );

        // The compare-and-set stops the second correction from double-cutting the value.
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_NextYieldMismatch.selector,
                address(sReserve),
                _STORED_NEXT_YIELD,
                40e18
            )
        );
        configTimelock.executeQueuedAction(secondActionId);

        assertEq(
            yieldRepo.getAssetConfig(address(sReserve)).nextYield,
            40e18,
            "first correction preserved"
        );
    }
}
