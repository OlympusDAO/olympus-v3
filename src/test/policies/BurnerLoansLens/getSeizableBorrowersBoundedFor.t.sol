// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansLensScanTest} from "./fixtures/BurnerLoansLensScanTest.sol";

// Boundary drivers repeat mock/view calls; expected reverts intentionally consume no return value.
// forge-lint: disable-start(calls-loop,unused-return)
contract BurnerLoansLensBoundedScanTest is BurnerLoansLensScanTest {
    // Scenarios: BLLENS-BOUNDED-P01.
    function test_whenScanLimitZero_whenStartingAtZero(
        address caller_,
        address actor_,
        uint256 limit_
    ) public {
        _canonicalScan();
        _expectNoScanWork();
        _assertEmptyBoundedPage(caller_, actor_, 0, limit_);
    }

    // Scenarios: BLLENS-BOUNDED-P15.
    function test_whenResultLimitZero_whenScanLimitPositive(
        address caller_,
        address actor_,
        uint256 count_
    ) public {
        _canonicalScan();
        count_ = bound(count_, 1, type(uint256).max);
        _expectNoScanWork();
        _assertEmptyBoundedPage(caller_, actor_, count_, 0);
    }

    // Scenarios: BLLENS-BOUNDED-P09.
    function test_whenScanAndResultLimitsAreOne(address caller_, address actor_) public {
        _canonicalRewardScan();
        vm.recordLogs();
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), 0, 1, 1);
        assertEq(borrowers, _one(_ALICE), "Exact eligible borrowers in canonical order");
        assertEq(cursor, 1, "First unexamined borrower index, or zero at the end");
        assertEq(reward, 7, "Selected page receives the mocked aggregate reward");
        assertEq(vm.getRecordedLogs().length, 0, "Bounded scan emits no logs");
    }

    // Scenarios: BLLENS-BOUNDED-P10.
    function test_whenScanLimitOne_whenResultLimitGreaterThanOne(
        address caller_,
        address actor_,
        uint256 limit_
    ) public {
        _canonicalRewardScan();
        limit_ = bound(limit_, 2, type(uint256).max);
        vm.recordLogs();
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), 0, 1, limit_);
        assertEq(borrowers, _one(_ALICE), "Exact eligible borrowers in canonical order");
        assertEq(cursor, 1, "First unexamined borrower index, or zero at the end");
        assertEq(reward, 7, "Selected page receives the mocked aggregate reward");
        assertEq(vm.getRecordedLogs().length, 0, "Bounded scan emits no logs");
    }

    // Scenarios: BLLENS-BOUNDED-P11.
    function test_whenScanLimitTwo_whenResultLimitAtLeastTwo(
        address caller_,
        address actor_,
        uint256 limit_
    ) public {
        _canonicalRewardScan();
        limit_ = bound(limit_, 2, type(uint256).max);
        vm.recordLogs();
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), 0, 2, limit_);
        assertEq(borrowers, _one(_ALICE), "Exact eligible borrowers in canonical order");
        assertEq(cursor, 2, "First unexamined borrower index, or zero at the end");
        assertEq(reward, 7, "Selected page receives the mocked aggregate reward");
        assertEq(vm.getRecordedLogs().length, 0, "Bounded scan emits no logs");
    }

    // Scenarios: BLLENS-BOUNDED-P02.
    function test_whenResultLimitOne_whenScanLimitGreaterThanOne(
        address caller_,
        address actor_,
        uint256 count_
    ) public {
        _canonicalRewardScan();
        count_ = bound(count_, 2, type(uint256).max);
        vm.recordLogs();
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), 0, count_, 1);
        assertEq(borrowers, _one(_ALICE), "Exact eligible borrowers in canonical order");
        assertEq(cursor, 1, "First unexamined borrower index, or zero at the end");
        assertEq(reward, 7, "Selected page receives the mocked aggregate reward");
        assertEq(vm.getRecordedLogs().length, 0, "Bounded scan emits no logs");
    }

    // Scenarios: BLLENS-BOUNDED-P12.
    function test_whenScanLimitThree_whenResultLimitTwo(address caller_, address actor_) public {
        _canonicalRewardScan();
        vm.recordLogs();
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), 0, 3, 2);
        assertEq(borrowers, _two(_ALICE, _CAROL), "Exact eligible borrowers in canonical order");
        assertEq(cursor, 3, "First unexamined borrower index, or zero at the end");
        assertEq(reward, 7, "Selected page receives the mocked aggregate reward");
        assertEq(vm.getRecordedLogs().length, 0, "Bounded scan emits no logs");
    }

    // Scenarios: BLLENS-BOUNDED-P13.
    function test_whenScanLimitThree_whenResultLimitGreaterThanTwo(
        address caller_,
        address actor_,
        uint256 limit_
    ) public {
        _canonicalRewardScan();
        limit_ = bound(limit_, 3, type(uint256).max);
        vm.recordLogs();
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), 0, 3, limit_);
        assertEq(borrowers, _two(_ALICE, _CAROL), "Exact eligible borrowers in canonical order");
        assertEq(cursor, 3, "First unexamined borrower index, or zero at the end");
        assertEq(reward, 7, "Selected page receives the mocked aggregate reward");
        assertEq(vm.getRecordedLogs().length, 0, "Bounded scan emits no logs");
    }

    // Scenarios: BLLENS-BOUNDED-P08.
    function test_whenScanLimitAtLeastFour_whenResultLimitTwo(
        address caller_,
        address actor_,
        uint256 count_
    ) public {
        _canonicalRewardScan();
        count_ = bound(count_, 4, type(uint256).max);
        vm.recordLogs();
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), 0, count_, 2);
        assertEq(borrowers, _two(_ALICE, _CAROL), "Exact eligible borrowers in canonical order");
        assertEq(cursor, 3, "First unexamined borrower index, or zero at the end");
        assertEq(reward, 7, "Selected page receives the mocked aggregate reward");
        assertEq(vm.getRecordedLogs().length, 0, "Bounded scan emits no logs");
    }

    // Scenarios: BLLENS-BOUNDED-P14.
    function test_whenScanLimitAtLeastFour_whenResultLimitGreaterThanTwo(
        address caller_,
        address actor_,
        uint256 count_,
        uint256 limit_
    ) public {
        _canonicalRewardScan();
        count_ = bound(count_, 4, type(uint256).max);
        limit_ = bound(limit_, 3, type(uint256).max);
        vm.recordLogs();
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), 0, count_, limit_);
        assertEq(borrowers, _two(_ALICE, _CAROL), "Exact eligible borrowers in canonical order");
        assertEq(cursor, 0, "First unexamined borrower index, or zero at the end");
        assertEq(reward, 7, "Selected page receives the mocked aggregate reward");
        assertEq(vm.getRecordedLogs().length, 0, "Bounded scan emits no logs");
    }

    // Scenarios: BLLENS-BOUNDED-P02.
    function test_givenEligibleFirstBorrower_whenResultLimitOne(
        address caller_,
        address actor_
    ) public {
        _canonicalRewardScan();
        vm.expectCall(
            address(_floan),
            abi.encodeCall(
                IFLOANv1.getActiveBorrowerAt,
                (_core.marketId(address(_asset)), uint256(1))
            ),
            uint64(0)
        );
        vm.prank(caller_);
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), 0, 4, 1);
        assertEq(borrowers, _one(_ALICE), "Result cap admits Alice only");
        assertEq(cursor, 1, "Stop before examining the next borrower");
        assertEq(reward, 7, "Reward is quoted only for the admitted page");
    }

    // Scenarios: BLLENS-BOUNDED-P16.
    function test_givenResultLimitReached_whenResuming(address caller_, address actor_) public {
        _canonicalRewardScan();
        vm.prank(caller_);
        (address[] memory first, uint256 firstCursor, uint256 firstReward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), 0, 4, 1);
        assertEq(first, _one(_ALICE), "First page contains Alice only");
        assertEq(firstCursor, 1, "First page stops before healthy Bob and eligible Carol");
        assertEq(firstReward, 7, "First page receives the mocked aggregate reward");

        vm.prank(caller_);
        (address[] memory second, uint256 secondCursor, uint256 secondReward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), firstCursor, 4, 1);
        assertEq(second, _one(_CAROL), "Resumed page finds Carol after healthy Bob");
        assertEq(secondCursor, 3, "Second page stops before healthy Dave");
        assertEq(secondReward, 7, "Second page receives its aggregate reward");

        vm.prank(caller_);
        (address[] memory last, uint256 finalCursor, uint256 lastReward) = _lens
            .getSeizableBorrowersBoundedFor(actor_, address(_asset), secondCursor, 4, 1);
        assertEq(last.length, 0, "Final page examines only healthy Dave");
        assertEq(finalCursor, 0, "Final page reaches the end");
        assertEq(lastReward, 0, "Final page selects no reward-bearing borrowers");
    }

    // Scenarios: BLLENS-BOUNDED-N01.
    function test_whenZeroLimitBoundariesSeeded() public {
        _canonicalScan();
        _expectNoScanWork();
        _assertEmptyBoundedPage(_ALICE, _BOB, 0, 0);
        _assertEmptyBoundedPage(_ALICE, _BOB, 0, 1);
        _assertEmptyBoundedPage(_ALICE, _BOB, 0, 2);
        _assertEmptyBoundedPage(_ALICE, _BOB, 0, 3);
        _assertEmptyBoundedPage(_ALICE, _BOB, 0, 4);
        _assertEmptyBoundedPage(_ALICE, _BOB, 0, type(uint256).max);
        _assertEmptyBoundedPage(_ALICE, _BOB, 1, 0);
        _assertEmptyBoundedPage(_ALICE, _BOB, 2, 0);
        _assertEmptyBoundedPage(_ALICE, _BOB, 3, 0);
        _assertEmptyBoundedPage(_ALICE, _BOB, 4, 0);
        _assertEmptyBoundedPage(_ALICE, _BOB, type(uint256).max, 0);
    }

    // Scenarios: BLLENS-BOUNDED-N01.
    function test_whenSingleResultLimitBoundariesSeeded() public {
        test_whenScanAndResultLimitsAreOne(_ALICE, _BOB);
        test_whenScanLimitOne_whenResultLimitGreaterThanOne(_ALICE, _BOB, 2);
        test_whenScanLimitOne_whenResultLimitGreaterThanOne(_ALICE, _BOB, 3);
        test_whenScanLimitOne_whenResultLimitGreaterThanOne(_ALICE, _BOB, 4);
        test_whenScanLimitOne_whenResultLimitGreaterThanOne(_ALICE, _BOB, type(uint256).max);
        test_whenResultLimitOne_whenScanLimitGreaterThanOne(_ALICE, _BOB, 2);
        test_whenScanLimitTwo_whenResultLimitAtLeastTwo(_ALICE, _BOB, 2);
        test_whenScanLimitTwo_whenResultLimitAtLeastTwo(_ALICE, _BOB, 3);
        test_whenScanLimitTwo_whenResultLimitAtLeastTwo(_ALICE, _BOB, 4);
        test_whenScanLimitTwo_whenResultLimitAtLeastTwo(_ALICE, _BOB, type(uint256).max);
        test_whenResultLimitOne_whenScanLimitGreaterThanOne(_ALICE, _BOB, 3);
        test_whenResultLimitOne_whenScanLimitGreaterThanOne(_ALICE, _BOB, 4);
        test_whenResultLimitOne_whenScanLimitGreaterThanOne(_ALICE, _BOB, type(uint256).max);
    }

    // Scenarios: BLLENS-BOUNDED-N01.
    function test_whenTwoResultsLimitBoundariesSeeded() public {
        test_whenScanLimitThree_whenResultLimitTwo(_ALICE, _BOB);
        test_whenScanLimitThree_whenResultLimitGreaterThanTwo(_ALICE, _BOB, 3);
        test_whenScanLimitThree_whenResultLimitGreaterThanTwo(_ALICE, _BOB, 4);
        test_whenScanLimitThree_whenResultLimitGreaterThanTwo(_ALICE, _BOB, type(uint256).max);
        test_whenScanLimitAtLeastFour_whenResultLimitTwo(_ALICE, _BOB, 4);
        test_whenScanLimitAtLeastFour_whenResultLimitGreaterThanTwo(_ALICE, _BOB, 4, 3);
        test_whenScanLimitAtLeastFour_whenResultLimitGreaterThanTwo(_ALICE, _BOB, 4, 4);
        test_whenScanLimitAtLeastFour_whenResultLimitGreaterThanTwo(
            _ALICE,
            _BOB,
            4,
            type(uint256).max
        );
        test_whenScanLimitAtLeastFour_whenResultLimitTwo(_ALICE, _BOB, type(uint256).max);
        test_whenScanLimitAtLeastFour_whenResultLimitGreaterThanTwo(
            _ALICE,
            _BOB,
            type(uint256).max,
            3
        );
        test_whenScanLimitAtLeastFour_whenResultLimitGreaterThanTwo(
            _ALICE,
            _BOB,
            type(uint256).max,
            4
        );
        test_whenScanLimitAtLeastFour_whenResultLimitGreaterThanTwo(
            _ALICE,
            _BOB,
            type(uint256).max,
            type(uint256).max
        );
    }

    // Scenarios: BLLENS-BOUNDED-N01.
    function test_whenCallerAndActorAreZero_whenBothLimitsMaximum() public {
        test_whenScanLimitAtLeastFour_whenResultLimitGreaterThanTwo(
            address(0),
            address(0),
            type(uint256).max,
            type(uint256).max
        );
    }

    // Scenarios: BLLENS-BOUNDED-P03.
    function test_whenStartVaries_thenUnlimitedResultsAgreeWithExistingScan(
        address caller_,
        uint256 start_,
        uint256 count_
    ) public {
        _canonicalScan();
        start_ = bound(start_, 0, 3);
        _mockWithdrawal(100e6, 100e6);
        _mockWithdrawal(300e6, 300e6);
        _mockWithdrawal(400e6, 400e6);
        (address[] memory expected, uint256 expectedCursor, uint256 expectedReward) = _lens
            .getSeizableBorrowersFor(caller_, address(_asset), start_, count_);
        vm.prank(caller_);
        (address[] memory actual, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(
                caller_,
                address(_asset),
                start_,
                count_,
                type(uint256).max
            );
        assertEq(actual, expected, "Unrestricted result cap retains existing scan behavior");
        assertEq(cursor, expectedCursor, "Existing and bounded cursors agree");
        assertEq(reward, expectedReward, "Existing and bounded reward calculations agree");
    }

    // Scenarios: BLLENS-BOUNDED-P04.
    function test_givenCoreUnavailable_whenScanned_thenNoUpstreamLifecycleGate(
        bool active_,
        bool enabled_
    ) public {
        _canonicalScan();
        _setCoreLifecycle(active_, enabled_);
        _mockWithdrawal(100e6, 100e6);
        (address[] memory borrowers, uint256 cursor, ) = _lens.getSeizableBorrowersBoundedFor(
            _ALICE,
            address(_asset),
            0,
            4,
            1
        );
        assertEq(
            borrowers,
            _one(_ALICE),
            "Plain Lens remains independent of Core operational state"
        );
        assertEq(cursor, 1, "Result cap still controls progress");
    }

    // Scenarios: BLLENS-BOUNDED-I01.
    function test_whenAssetIsUnknown_reverts(
        address asset_,
        uint256 start_,
        uint256 count_,
        uint256 limit_
    ) public {
        vm.assume(!_core.isAssetRegistered(asset_));
        _expectNoScanWork();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset_
            )
        );
        _lens.getSeizableBorrowersBoundedFor(_ALICE, asset_, start_, count_, limit_);
    }

    // Scenarios: BLLENS-BOUNDED-I02.
    function test_whenStartIsInvalid_reverts(
        uint256 start_,
        uint256 population_,
        uint256 count_,
        uint256 limit_
    ) public {
        population_ = bound(population_, 1, type(uint256).max);
        start_ = bound(start_, population_, type(uint256).max);
        _mockCount(population_);
        _expectNoScanWork();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                start_,
                population_
            )
        );
        _lens.getSeizableBorrowersBoundedFor(_ALICE, address(_asset), start_, count_, limit_);
    }

    // Scenarios: BLLENS-BOUNDED-P05.
    function test_givenEmptyMarket_whenScanned_thenNoPricingReads(
        uint256 count_,
        uint256 limit_
    ) public {
        _expectNoScanWork();
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(_ALICE, address(_asset), 0, count_, limit_);
        assertEq(borrowers.length, 0, "Empty market returns no candidates");
        assertEq(cursor, 0, "Empty market cursor");
        assertEq(reward, 0, "Empty market reward");
    }

    // Scenarios: BLLENS-BOUNDED-I02.
    function test_givenEmptyMarket_whenStartNonzero_reverts(
        uint256 start_,
        uint256 count_,
        uint256 limit_
    ) public {
        start_ = bound(start_, 1, type(uint256).max);
        _expectNoScanWork();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                start_,
                uint256(0)
            )
        );
        _lens.getSeizableBorrowersBoundedFor(_ALICE, address(_asset), start_, count_, limit_);
    }

    // Scenarios: BLLENS-BOUNDED-I02.
    function test_whenMaximumStartBoundariesSeeded_reverts() public {
        _expectNoScanWork();
        uint256 maximum = type(uint256).max;
        uint256[3] memory populations = [maximum, uint256(1), uint256(0)];
        for (uint256 i; i < populations.length; ++i) {
            _mockCount(populations[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansLens.BurnerLoansLens_InvalidStart.selector,
                    maximum,
                    populations[i]
                )
            );
            _lens.getSeizableBorrowersBoundedFor(
                _ALICE,
                address(_asset),
                maximum,
                i == 1 ? maximum : 0,
                i == 1 ? maximum : 0
            );
        }
    }

    // Scenarios: BLLENS-BOUNDED-P06.
    function test_givenPopulatedMarket_whenResultLimitZero_thenNoPricingReads(
        uint256 count_
    ) public {
        _canonicalScan();
        _expectNoScanWork();
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(_ALICE, address(_asset), 1, count_, 0);
        assertEq(borrowers.length, 0, "Zero result cap selects nothing");
        assertEq(cursor, 1, "Zero result cap preserves the valid start");
        assertEq(reward, 0, "Zero result cap has no reward");
    }

    // Scenarios: BLLENS-BOUNDED-P07.
    function test_givenPopulatedMarket_whenScanLimitZero_thenNoPricingReads(uint256 limit_) public {
        _canonicalScan();
        _expectNoScanWork();
        (address[] memory borrowers, uint256 cursor, uint256 reward) = _lens
            .getSeizableBorrowersBoundedFor(_ALICE, address(_asset), 1, 0, limit_);
        assertEq(borrowers.length, 0, "Zero scan cap selects nothing");
        assertEq(cursor, 1, "Zero scan cap preserves the valid start");
        assertEq(reward, 0, "Zero scan cap has no reward");
    }
}
