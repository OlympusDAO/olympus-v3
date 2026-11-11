// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Libraries
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTaskProgressTest} from "../fixtures/BurnerLoansSeizerTaskProgressTest.sol";
import {Actions, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";

// Small fixture identities and borrower populations are deliberate test boundaries.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,calls-loop)
contract BurnerLoansSeizerTaskExecuteIntegrationTest is BurnerLoansSeizerTaskProgressTest {
    error ScanReadFailed();
    error SettlementFailed();

    function setUp() public override {
        super.setUp();
        _task.addAsset(address(_asset));
        _task.addAsset(address(_otherAsset));
    }

    // Scenarios: BLSEIZ-EXECUTE-P05, BLSEIZ-SELF-EXECUTE-P02, BLSEIZ-SELF-EXECUTE-P03.
    function test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles()
        public
    {
        for (uint256 i; i < 50; ++i) _seedDebt(address(uint160(0x10000 + i)), 10e6, 1e9);
        _mature();
        _task.execute();
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            25,
            "First A visit settles 25 borrowers"
        );
        assertEq(_task.assetCursor(address(_asset)), 0, "Compacted borrower cursor remains valid");
        assertEq(_task.nextAssetIndex(), 1, "B gets the next turn");
        _task.execute();
        assertEq(_inventory.activePrincipalOhm(), 25e9, "B visit cannot process A again");
        assertEq(_task.nextAssetIndex(), 0, "A follows B");
        _task.execute();
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            0,
            "Second A visit settles the remaining 25 without a reset-only turn"
        );
        assertEq(_inventory.activePrincipalOhm(), 0, "Defaults reconcile all Inventory principal");
        assertEq(
            _floan.getMarketCollateral(_core.marketId(address(_asset))),
            0,
            "All seized collateral leaves FLOAN accounting"
        );
        assertEq(_asset.balanceOf(address(_task)), 0, "Task has no keeper reward or custody");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P09.
    function test_givenSparseCandidates_whenScanLimitExceedsBatchLimit_thenNoCandidateIsDiscarded()
        public
    {
        _canonicalScan();
        _mockPosition(_ALICE, 100e6, 10e9, uint48(block.timestamp + 1 days), 1);
        _mockPosition(_CAROL, 300e6, 30e9, uint48(block.timestamp), 1);
        _task.setScanLimits(4, 1);
        bytes memory settlement = abi.encodeCall(
            _liquidation.seize,
            (address(_asset), _one(_CAROL))
        );
        vm.mockCall(
            address(_liquidation),
            settlement,
            abi.encode(address(_asset), uint256(0), uint256(0))
        );
        vm.expectCall(address(_liquidation), settlement, uint64(1));
        vm.expectCall(
            address(_floan),
            abi.encodeCall(
                IFLOANv1.getActiveBorrowerAt,
                (_core.marketId(address(_asset)), uint256(3))
            ),
            uint64(0)
        );
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "Sparse scanning uses only A turn");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P05.
    function test_givenStaleCursor_whenAssetVisited_thenRecoveryAndSettlementShareOneTurn() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _mature();
        vm.mockCall(
            address(_lens),
            _boundedScan(address(_asset), 0),
            abi.encode(new address[](0), uint256(3), uint256(0))
        );
        _task.execute();
        vm.clearMockedCalls();
        _task.execute(); // B receives its turn before A repairs the stale cursor.
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 3), uint64(0));
        vm.expectCall(address(_lens), _boundedScan(address(_asset), 0), uint64(1));
        _task.execute();
        assertEq(
            _inventory.activePrincipalOhm(),
            0,
            "A repairs its cursor and settles on the same visit"
        );
        assertEq(_task.assetCursor(address(_asset)), 0, "Empty borrower cursor is zero");
        assertEq(_task.nextAssetIndex(), 1, "Recovery still rotates to B");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P11.
    function test_givenBorrowersRepaidBetweenVisits_whenCursorIsStale_thenSameVisitSeizesRemainingDebt()
        public
    {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _seedDebt(_CAROL, 10e6, 1e9);
        _seedDebt(_DAVE, 10e6, 1e9);
        _task.setScanLimits(3, 1);
        _task.execute(); // All healthy: cursor 3 of 4.
        assertEq(_task.assetCursor(address(_asset)), 3, "Healthy scan advances past prefix");
        _repay(_BOB, 1e9);
        _repay(_CAROL, 1e9); // List now contains only Alice and Dave.
        _mature();
        _task.execute(); // B turn.
        _task.execute(); // A resets 3 -> 0 and settles one borrower immediately.
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            1,
            "Stale cursor recovery performs settlement on this visit"
        );
        assertEq(_inventory.activePrincipalOhm(), 1e9, "One remaining principal reconciled");
        assertEq(_task.nextAssetIndex(), 1, "B keeps its next turn");
        assertEq(_task.assetCursor(address(_otherAsset)), 0, "Other asset cursor unchanged");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P12.
    function test_givenThirdPartySeizesBetweenVisits_whenCursorIsStale_thenSameVisitSeizesRemainingDebt()
        public
    {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _seedDebt(_CAROL, 10e6, 1e9);
        _seedDebt(_DAVE, 10e6, 1e9);
        _task.setScanLimits(3, 1);
        _task.execute();
        _mature();
        vm.prank(makeAddr("external keeper"));
        _liquidation.seize(address(_asset), _two(_BOB, _CAROL));
        assertEq(
            _task.assetCursor(address(_asset)),
            3,
            "Foreign seizure does not edit Task cursor"
        );
        _task.execute();
        _task.execute();
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            1,
            "Recovery settles another borrower without wasting A visit"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            1e9,
            "Foreign and Task seizures reconcile principal"
        );
        assertEq(_task.nextAssetIndex(), 1, "A recovery rotates normally");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P13.
    function test_givenHealthyPrefix_whenBoundedScansRepeat_thenEligibleSuffixRemainsReachable()
        public
    {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _mature();
        _seedDebt(_CAROL, 10e6, 1e9);
        _seedDebt(_DAVE, 10e6, 1e9);
        // Repaying Alice swaps unexpired Dave to index zero, ahead of expired Bob.
        _repay(_ALICE, 1e9);
        _task.setScanLimits(1, 1);
        _task.execute();
        assertEq(_task.assetCursor(address(_asset)), 1, "First scan stops after healthy prefix");
        _task.execute();
        _task.execute();
        assertEq(
            _lens.getPosition(address(_asset), _BOB).debtOhm,
            0,
            "Expired borrower behind healthy prefix is settled"
        );
        assertEq(_inventory.activePrincipalOhm(), 2e9, "Only two healthy borrowers remain");
        assertEq(_task.nextAssetIndex(), 1, "Suffix discovered on second A visit");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P07, BLSEIZ-EXECUTE-P02.
    function test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _mature();
        vm.mockCallRevert(
            address(_liquidation),
            abi.encodeCall(_liquidation.seize, (address(_asset), _one(_ALICE))),
            abi.encodeWithSelector(SettlementFailed.selector)
        );
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureFailed(address(_asset), SettlementFailed.selector);
        _task.execute();
        assertEq(_task.nextAssetIndex(), 1, "Failed settlement does not block B");
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "Failed settlement preserves borrower cursor"
        );
        assertEq(_inventory.activePrincipalOhm(), 1e9, "Failed batch changes no principal");
        assertEq(_lens.getPosition(address(_asset), _ALICE).debtOhm, 1e9, "Debt remains for retry");
        vm.clearMockedCalls();
        _task.execute();
        _task.execute();
        assertEq(_inventory.activePrincipalOhm(), 0, "Later A visit retries the full batch");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P10.
    function test_givenUnsupportedEntry_whenExecuted_thenScanFailureIsIsolated() public {
        BurnerLoansSeizerTask task = _newTask();
        address unsupported = makeAddr("unsupported");
        // Model a registration report that changes after admission or an older task entry.
        vm.mockCall(
            address(_core),
            abi.encodeCall(_core.isAssetRegistered, (unsupported)),
            abi.encode(true)
        );
        task.addAsset(unsupported);
        task.addAsset(address(_asset));
        vm.clearMockedCalls();
        vm.expectEmit(true, false, false, true, address(task));
        emit IBurnerLoansSeizerTask.ScanFailed(
            unsupported,
            IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector
        );
        task.execute();
        assertEq(task.nextAssetIndex(), 1, "Unsupported entry does not block registered asset");
        assertEq(task.assetCursor(unsupported), 0, "Unsupported entry has no borrower progress");
        task.execute();
        assertEq(task.nextAssetIndex(), 0, "Registered asset remains reachable");
    }

    // Scenarios: BLSEIZ-EXECUTE-P07.
    function test_givenOuterGasBelowConfiguredLimit_whenExecuted_thenCleanupAndRotationSurvive()
        public
    {
        _seedDebt(_ALICE, 10e6, 1e9);
        _mature();
        _task.execute{gas: 150_000}();
        assertEq(
            _task.nextAssetIndex(),
            1,
            "Outer cleanup survives an oversized configured body budget"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            1e9,
            "Gas exhaustion cannot partially default a borrower"
        );
    }

    // Scenarios: BLSEIZ-EXECUTE-P08.
    function test_givenTaskExhaustsGas_whenHeartRunsTasks_thenLaterTaskExecutes() public {
        MockPeriodicTaskManager manager = new MockPeriodicTaskManager(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(manager));
        _rolesAdmin.grantRole(HEART_ROLE, address(manager));
        MockPeriodicTask later = new MockPeriodicTask();
        manager.addPeriodicTask(address(_task));
        manager.addPeriodicTask(address(later));
        _task.setExecutionGasLimit(1);
        manager.executeAllTasks{gas: 500_000}();
        assertEq(later.count(), 1, "Bounded task failure does not block later Heart work");
        assertEq(_task.nextAssetIndex(), 1, "Heartbeat failure preserves asset fairness");
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P06.
    function test_givenEmptyMarketWithStaleCursor_whenVisited_thenRecoveryCompletesSameTurn()
        public
    {
        vm.mockCall(
            address(_lens),
            _boundedScan(address(_asset), 0),
            abi.encode(new address[](0), uint256(1), uint256(0))
        );
        _task.execute();
        vm.clearMockedCalls();
        _task.execute(); // B receives its ordinary turn.
        _expectNoRiskReads();
        vm.expectEmit(true, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.SeizureExecuted(address(_asset), 0, 0, 0);
        _task.execute();
        assertEq(
            _task.assetCursor(address(_asset)),
            0,
            "Empty-market stale cursor repairs within this visit"
        );
        assertEq(_task.nextAssetIndex(), 1, "Repair still gives B the next turn");
    }

    // Scenarios: BLSEIZ-EXECUTE-P12.
    function test_givenLastAsset_whenSelfCallFails_thenRotationWrapsAndBorrowerCursorsStayUnchanged()
        public
    {
        _seedDebt(_ALICE, 10e6, 1e9);
        _seedDebt(_BOB, 10e6, 1e9);
        _seedDebt(_CAROL, 10e6, 1e9);
        _seedDebt(_DAVE, 10e6, 1e9);
        _task.setScanLimits(3, 1);
        _task.execute();
        assertEq(_task.assetCursor(address(_asset)), 3, "A saved a nonzero borrower cursor");
        assertEq(_task.nextAssetIndex(), 1, "Last asset B is next");
        vm.mockCallRevert(
            address(_task),
            abi.encodeCall(_task.selfExecuteTask, ()),
            abi.encodeWithSelector(SettlementFailed.selector)
        );
        vm.expectEmit(false, false, false, true, address(_task));
        emit IBurnerLoansSeizerTask.ExecutionFailed(SettlementFailed.selector);
        _task.execute();
        assertEq(_task.nextAssetIndex(), 0, "Whole-body failure rotates last asset back to first");
        assertEq(
            _task.assetCursor(address(_asset)),
            3,
            "A borrower progress is independent of B failure"
        );
        assertEq(
            _task.assetCursor(address(_otherAsset)),
            0,
            "Failed B body leaves its borrower cursor unchanged"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            4e9,
            "Outer recovery changes no borrower principal"
        );
    }

    function test_givenMaturedPosition_seizesWithoutKeeperReward() public {
        _seedDebt(_ALICE, 10e6, 1e9);
        _mature();
        address treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
        uint256 treasuryBefore = _asset.balanceOf(treasury);
        _task.execute();
        assertEq(_lens.getPosition(address(_asset), _ALICE).debtOhm, 0, "Position debt cleared");
        assertEq(
            _lens.getPosition(address(_asset), _ALICE).depositedCollateral,
            0,
            "Position collateral cleared"
        );
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory active principal cleared");
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            0,
            "Canonical principal cleared"
        );
        assertEq(_asset.balanceOf(address(_task)), 0, "Task receives no keeper reward");
        // One position with 10e6 collateral units; Task's seizer role earns no reward.
        assertEq(
            _asset.balanceOf(treasury) - treasuryBefore,
            10e6,
            "Treasury receives all seized collateral"
        );
        assertEq(
            _mintr().mintApproval(address(_inventory)),
            _inventory.desiredMintApproval(),
            "Mint approval reconciled"
        );
        assertEq(
            _mintr().mintApproval(address(_inventory)),
            _inventory.globalDebtCapOhm(),
            "Zero principal restores the full global cap"
        );
    }

    function test_givenNoSeizableBorrowers_doesNotRestoreUnrecordedDeficit() public {
        MINTRv1 mintr = _mintr();
        uint256 beforeApproval = mintr.mintApproval(address(_inventory));
        vm.prank(address(_inventory));
        mintr.decreaseMintApproval(address(_inventory), 1);
        _task.execute();
        assertEq(
            _mintr().mintApproval(address(_inventory)),
            beforeApproval - 1,
            "Empty scan preserves conservative deficit"
        );
        assertEq(_inventory.activePrincipalOhm(), 0, "Empty market has no principal");
    }

    function test_givenNoManagedAssets_doesNotRestoreUnrecordedDeficit() public {
        _task.removeAsset(address(_asset));
        _task.removeAsset(address(_otherAsset));
        MINTRv1 mintr = _mintr();
        uint256 beforeApproval = mintr.mintApproval(address(_inventory));
        vm.prank(address(_inventory));
        mintr.decreaseMintApproval(address(_inventory), 1);
        _task.execute();
        assertEq(
            _mintr().mintApproval(address(_inventory)),
            beforeApproval - 1,
            "Empty registry preserves conservative deficit"
        );
    }

    function _mintr() private view returns (MINTRv1) {
        return MINTRv1(address(_kernel.getModuleForKeycode(toKeycode("MINTR"))));
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,calls-loop)
