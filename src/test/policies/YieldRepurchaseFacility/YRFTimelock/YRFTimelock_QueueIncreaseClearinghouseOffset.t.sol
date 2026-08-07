// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYRFTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYRFTimelock.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {YRFTimelock} from "src/policies/YieldRepurchaseFacility/YRFTimelock.sol";
import {YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {YRFTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YRFTimelock/YRFTimelockTestBase.sol";

contract YRFTimelockTests_QueueIncreaseClearinghouseOffset is YRFTimelockTestBase {
    uint256 internal constant _RECEIVABLES = 1_000e18;

    function setUp() public override {
        super.setUp();
        clearinghouse.setPrincipalReceivables(_RECEIVABLES);
    }

    // queueIncreaseClearinghouseOffset
    // given the caller does not hold the yrf_admin role
    //  when queueing an offset increase
    //   then it reverts with ROLES_RequireRole(yrf_admin)
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != yrfAdmin);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, YRF_ADMIN_ROLE));
        yrfTimelock.queueIncreaseClearinghouseOffset(address(clearinghouse), 250e18);
    }

    // queueIncreaseClearinghouseOffset
    // given the timelock policy is disabled
    //  when queueing an offset increase
    //   then it reverts with NotEnabled and no action id is consumed
    function test_givenTimelockDisabled_reverts() public {
        vm.prank(guardian);
        yrfTimelock.disable("");

        vm.prank(yrfAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        yrfTimelock.queueIncreaseClearinghouseOffset(address(clearinghouse), 250e18);

        assertEq(yrfTimelock.nextActionId(), 1, "next action id");
    }

    // queueIncreaseClearinghouseOffset
    // given the facility slot has not been set
    //  when queueing an offset increase
    //   then it reverts with IYRFTimelock_FacilityNotSet
    function test_givenFacilityNotSet_reverts() public {
        YRFTimelock unwired = _deployUnwiredTimelock();

        vm.prank(yrfAdmin);
        vm.expectRevert(IYRFTimelock.IYRFTimelock_FacilityNotSet.selector);
        unwired.queueIncreaseClearinghouseOffset(address(clearinghouse), 250e18);
    }

    // queueIncreaseClearinghouseOffset
    // given the Clearinghouse address is zero
    //  when queueing an offset increase
    //   then it reverts with the facility's BadInput("clearinghouse") (the queue delegates
    //   the value checks to the facility's validator)
    function test_givenZeroClearinghouse_reverts() public {
        vm.prank(yrfAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.BadInput.selector, "clearinghouse"));
        yrfTimelock.queueIncreaseClearinghouseOffset(address(0), 250e18);
    }

    // queueIncreaseClearinghouseOffset
    // given the resulting offset exceeds the current principalReceivables
    //  when queueing any such increase
    //   then it reverts with IYieldRepurchaseFacilityV2_OffsetExceedsReceivables
    function test_givenOffsetAboveReceivables_reverts(uint256 additionalOffset_) public {
        additionalOffset_ = bound(additionalOffset_, _RECEIVABLES + 1, type(uint256).max);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_OffsetExceedsReceivables
                    .selector,
                address(clearinghouse),
                additionalOffset_,
                _RECEIVABLES
            )
        );
        yrfTimelock.queueIncreaseClearinghouseOffset(address(clearinghouse), additionalOffset_);
    }

    // queueIncreaseClearinghouseOffset
    // given an existing offset
    //  when queueing an increase whose sum with the existing offset exceeds receivables
    //   then it reverts (the queue validates the cumulative offset, not the increment)
    function test_givenExistingOffset_queueValidatesAgainstSum() public {
        vm.prank(guardian);
        yieldRepo.increaseClearinghouseOffset(address(clearinghouse), 600e18);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_OffsetExceedsReceivables
                    .selector,
                address(clearinghouse),
                1_100e18,
                _RECEIVABLES
            )
        );
        yrfTimelock.queueIncreaseClearinghouseOffset(address(clearinghouse), 500e18);

        // The remaining headroom is still queueable.
        uint64 actionId = _queueIncreaseClearinghouseOffset(address(clearinghouse), 400e18);
        assertEq(actionId, 1, "action id");
    }

    // queueIncreaseClearinghouseOffset
    // given the resulting offset equals the current principalReceivables
    //  when queueing the increase
    //   then the action is queued (inclusive boundary)
    function test_givenOffsetAtReceivables_queuesAction() public {
        uint64 actionId = _queueIncreaseClearinghouseOffset(address(clearinghouse), _RECEIVABLES);

        assertEq(actionId, 1, "action id");
    }

    // queueIncreaseClearinghouseOffset
    // given the Clearinghouse contract does not expose principalReceivables (read as zero)
    //  when queueing a non-zero increase
    //   then it reverts with IYieldRepurchaseFacilityV2_OffsetExceedsReceivables
    function test_givenClearinghouseWithoutReceivables_revertsForNonZeroOffset() public {
        // A contract without the selector reverts inside the call, which the try/catch reads
        // as zero receivables. (A codeless address instead fails the compiler's code check,
        // which try/catch does not catch, identically at queue and execution time.)
        address unknownClearinghouse = address(reserve);

        vm.prank(yrfAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_OffsetExceedsReceivables
                    .selector,
                unknownClearinghouse,
                1,
                0
            )
        );
        yrfTimelock.queueIncreaseClearinghouseOffset(unknownClearinghouse, 1);
    }

    // queueIncreaseClearinghouseOffset
    // given a zero increase on a Clearinghouse contract with zero receivables
    //  when queueing and executing the increase
    //   then both succeed as a no-op (the try/catch zero-read matches on both sides)
    function test_givenZeroAdditionalOffsetOnZeroReceivables_queuesAction() public {
        address unknownClearinghouse = address(reserve);

        uint64 actionId = _queueIncreaseClearinghouseOffset(unknownClearinghouse, 0);
        _warpToExecutable(yrfTimelock, actionId);
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.clearinghouseOffset(unknownClearinghouse), 0, "offset unchanged");
    }

    // queueIncreaseClearinghouseOffset
    // given any increase within the current receivables headroom
    //  when the yrf_admin queues the increase
    //   then the action is stored with the queue events and timelock timestamps
    function test_givenYrfAdminCaller_whenOffsetWithinReceivables_queuesAction(
        uint256 additionalOffset_
    ) public {
        additionalOffset_ = bound(additionalOffset_, 0, _RECEIVABLES);
        uint256 queuedAt = vm.getBlockTimestamp();
        ITimelockBatchQueue.BatchAction[] memory actions = _singleAction(
            address(yieldRepo),
            IYieldRepurchaseFacilityV2.increaseClearinghouseOffset.selector,
            abi.encode(address(clearinghouse), additionalOffset_)
        );

        _expectActionQueued(yrfTimelock, 1, yrfAdmin, actions);
        uint64 actionId = _queueIncreaseClearinghouseOffset(
            address(clearinghouse),
            additionalOffset_
        );

        assertEq(actionId, 1, "action id");
        _assertQueuedSingleAction(yrfTimelock, actionId, queuedAt, actions[0]);
    }

    // queueIncreaseClearinghouseOffset
    // given a queued offset increase
    //  when any caller executes within the execution window
    //   then the cumulative offset is increased and ClearinghouseOffsetSet is emitted
    function test_givenDelayElapsed_executesAction(uint48 elapsed_) public {
        uint256 queuedAt = vm.getBlockTimestamp();
        uint64 actionId = _queueIncreaseClearinghouseOffset(address(clearinghouse), 250e18);
        elapsed_ = uint48(
            bound(elapsed_, yrfTimelockDelay, yrfTimelockDelay + yrfTimelock.EXECUTION_WINDOW())
        );
        vm.warp(queuedAt + elapsed_);

        vm.expectEmit(true, false, false, true, address(yieldRepo));
        emit IYieldRepurchaseFacilityV2.ClearinghouseOffsetSet(address(clearinghouse), 250e18);
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.clearinghouseOffset(address(clearinghouse)), 250e18, "offset increased");
    }

    // queueIncreaseClearinghouseOffset
    // given receivables were repaid below the queued bound during the delay
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityV2_OffsetExceedsReceivables (live re-check)
    function test_givenReceivablesRepaidAfterQueue_executionReverts() public {
        uint64 actionId = _queueIncreaseClearinghouseOffset(address(clearinghouse), 800e18);
        clearinghouse.setPrincipalReceivables(500e18);
        _warpToExecutable(yrfTimelock, actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_OffsetExceedsReceivables
                    .selector,
                address(clearinghouse),
                800e18,
                500e18
            )
        );
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(yieldRepo.clearinghouseOffset(address(clearinghouse)), 0, "offset unchanged");
    }

    // queueIncreaseClearinghouseOffset
    // given the offset was increased directly by the admin so the queued increase overflows
    //  when the queued action executes
    //   then it reverts with IYieldRepurchaseFacilityV2_OffsetExceedsReceivables
    function test_givenOffsetIncreasedDirectlyAfterQueue_executionReverts() public {
        uint64 actionId = _queueIncreaseClearinghouseOffset(address(clearinghouse), 800e18);
        vm.prank(guardian);
        yieldRepo.increaseClearinghouseOffset(address(clearinghouse), 300e18);
        _warpToExecutable(yrfTimelock, actionId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_OffsetExceedsReceivables
                    .selector,
                address(clearinghouse),
                1_100e18,
                _RECEIVABLES
            )
        );
        yrfTimelock.executeQueuedAction(actionId);

        assertEq(
            yieldRepo.clearinghouseOffset(address(clearinghouse)),
            300e18,
            "direct increase preserved"
        );
    }

    // queueIncreaseClearinghouseOffset
    // given two pending increases whose sum stays within receivables (no pending slot)
    //  when both execute
    //   then both apply cumulatively
    function test_givenTwoPendingIncreasesWithinReceivables_bothExecute() public {
        uint64 firstActionId = _queueIncreaseClearinghouseOffset(address(clearinghouse), 400e18);
        uint64 secondActionId = _queueIncreaseClearinghouseOffset(address(clearinghouse), 500e18);
        _warpToExecutable(yrfTimelock, secondActionId);

        yrfTimelock.executeQueuedAction(firstActionId);
        assertEq(
            yieldRepo.clearinghouseOffset(address(clearinghouse)),
            400e18,
            "first increase applied"
        );

        yrfTimelock.executeQueuedAction(secondActionId);
        assertEq(
            yieldRepo.clearinghouseOffset(address(clearinghouse)),
            900e18,
            "increases accumulated"
        );
    }
}
