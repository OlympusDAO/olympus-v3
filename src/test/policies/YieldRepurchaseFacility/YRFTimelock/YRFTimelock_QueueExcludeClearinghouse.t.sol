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

contract YRFTimelockTests_QueueExcludeClearinghouse is YRFTimelockTestBase {
    address internal includedClearinghouse;

    function setUp() public override {
        super.setUp();
        includedClearinghouse = makeAddr("includedClearinghouse");
    }

    // queueExcludeClearinghouse
    // given the caller does not hold the yrf_admin role
    //  when queueing a Clearinghouse exclusion
    //   then it reverts with ROLES_RequireRole(yrf_admin)
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != yrfAdmin);
        _includeClearinghouse();

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        yrfTimelock.queueExcludeClearinghouse(includedClearinghouse);
    }

    // queueExcludeClearinghouse
    // given the timelock policy is disabled
    //  when queueing a Clearinghouse exclusion
    //   then it reverts with NotEnabled and no action id is consumed
    function test_givenTimelockDisabled_reverts() public {
        _includeClearinghouse();
        vm.prank(guardian);
        yrfTimelock.disable("");

        vm.prank(yrfAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        yrfTimelock.queueExcludeClearinghouse(includedClearinghouse);

        assertEq(yrfTimelock.nextActionId(), 1, "next action id");
    }

    // queueExcludeClearinghouse
    // given the facility slot has not been set
    //  when queueing a Clearinghouse exclusion
    //   then it reverts with IYRFTimelock_FacilityNotSet
    function test_givenFacilityNotSet_reverts() public {
        _includeClearinghouse();
        YRFTimelock unwired = _deployUnwiredTimelock();

        vm.prank(yrfAdmin);
        vm.expectRevert(IYRFTimelock.IYRFTimelock_FacilityNotSet.selector);
        unwired.queueExcludeClearinghouse(includedClearinghouse);
    }

    // queueExcludeClearinghouse
    // given the Clearinghouse is not explicitly included
    //  when queueing the exclusion
    //   then it reverts with IYieldRepurchaseFacilityV2_ClearinghouseNotIncluded
    function test_givenClearinghouseNotIncluded_reverts() public {
        vm.prank(yrfAdmin);
        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_ClearinghouseNotIncluded.selector
        );
        yrfTimelock.queueExcludeClearinghouse(includedClearinghouse);
    }

    // queueExcludeClearinghouse
    // given the Clearinghouse is explicitly included
    //  when the yrf_admin queues the exclusion
    //   then the action is stored with the queue events and timelock timestamps
    function test_givenYrfAdminCaller_whenClearinghouseIncluded_queuesAction() public {
        _includeClearinghouse();
        uint256 queuedAt = vm.getBlockTimestamp();
        ITimelockBatchQueue.BatchAction[] memory actions = _singleAction(
            address(yieldRepo),
            IYieldRepurchaseFacilityV2.excludeClearinghouse.selector,
            abi.encode(includedClearinghouse)
        );

        _expectActionQueued(yrfTimelock, 1, yrfAdmin, actions);
        uint64 actionId = _queueExcludeClearinghouse(includedClearinghouse);

        assertEq(actionId, 1, "action id");
        _assertQueuedSingleAction(yrfTimelock, actionId, queuedAt, actions[0]);
    }

    // queueExcludeClearinghouse
    // given a queued exclusion
    //  when any caller executes within the execution window
    //   then the inclusion is removed and ClearinghouseExcluded is emitted
    function test_givenDelayElapsed_executesAction(uint48 elapsed_) public {
        _includeClearinghouse();
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueExcludeClearinghouse(includedClearinghouse);
        elapsed_ = uint48(
            bound(elapsed_, yrfTimelockDelay, yrfTimelockDelay + yrfTimelock.EXECUTION_WINDOW())
        );
        vm.warp(queuedAt + elapsed_);

        vm.expectEmit(true, false, false, true, address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.ClearinghouseExcluded(includedClearinghouse);
        yrfTimelock.executeQueuedAction(actionId);

        assertFalse(
            yieldRepo.isClearinghouseIncluded(includedClearinghouse),
            "clearinghouse excluded"
        );
    }

    // queueExcludeClearinghouse
    // given the Clearinghouse was excluded directly by the admin after the queue
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityV2_ClearinghouseNotIncluded
    function test_givenClearinghouseExcludedAfterQueue_executionReverts() public {
        _includeClearinghouse();
        uint64 actionId = _queueExcludeClearinghouse(includedClearinghouse);
        vm.prank(guardian);
        yieldRepo.excludeClearinghouse(includedClearinghouse);
        _warpToExecutable(yrfTimelock, actionId);

        vm.expectRevert(
            IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_ClearinghouseNotIncluded.selector
        );
        yrfTimelock.executeQueuedAction(actionId);
    }

    // queueExcludeClearinghouse
    // given the Clearinghouse was excluded and re-included after the queue
    //  when the queued action executes
    //   then it executes (the facility re-validates against the live inclusion flag)
    function test_givenClearinghouseReIncludedAfterQueue_executesAction() public {
        _includeClearinghouse();
        uint64 actionId = _queueExcludeClearinghouse(includedClearinghouse);
        vm.startPrank(guardian);
        yieldRepo.excludeClearinghouse(includedClearinghouse);
        yieldRepo.includeClearinghouse(includedClearinghouse);
        vm.stopPrank();
        _warpToExecutable(yrfTimelock, actionId);

        yrfTimelock.executeQueuedAction(actionId);

        assertFalse(
            yieldRepo.isClearinghouseIncluded(includedClearinghouse),
            "clearinghouse excluded"
        );
    }

    // ========== HELPERS ========== //

    function _includeClearinghouse() private {
        vm.prank(guardian);
        yieldRepo.includeClearinghouse(includedClearinghouse);
    }
}
