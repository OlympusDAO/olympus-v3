// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";

// Libraries
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";
import {MockBurnerLoansYieldClaimerTaskTarget} from "./MockBurnerLoansYieldClaimerTaskTarget.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.
// Bounded test loops intentionally call fixtures, assertions, and the task under test.
// forge-lint: disable-start(unsafe-typecast,calls-loop)

contract BurnerLoansYieldClaimerTaskExecuteTest is BurnerLoansYieldClaimerTaskTest {
    modifier givenDisabled() {
        vm.prank(_emergency);
        claimer.disable("");
        _;
    }

    modifier givenExecutionGasLimit(uint32 gasLimit_) {
        vm.prank(admin);
        claimer.setExecutionGasLimit(gasLimit_);
        _;
    }

    modifier givenAssetViewReverts() {
        target.setAssetViewReverts(true);
        _;
    }

    // Scenarios: BLYC-EXECUTE-A01.
    function test_givenCallerWithoutHeartRole_reverts(
        address caller_,
        bool targetActive_,
        bool targetEnabled_
    ) public {
        vm.assume(caller_ != heart);
        _setTargetLifecycle(targetActive_, targetEnabled_);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE));
        vm.prank(caller_);
        claimer.execute();
    }

    // Scenarios: BLYC-EXECUTE-P01.
    function test_givenClaimSucceeds_callsBurnerLoans() public {
        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 1, "claim calls");
        assertEq(target.lastClaimedAsset(), target.getAssetAt(0), "claimed asset");
        assertEq(claimer.nextAssetIndex(), 0, "single-asset cursor wraps");
        assertEq(vm.getRecordedLogs().length, 0, "claimer event count");
    }

    // Scenarios: BLYC-EXECUTE-P01.
    function test_givenMultipleClaimsSucceed_claimsEveryAsset() public {
        address[] memory assets = new address[](3);
        assets[0] = makeAddr("firstSuccessfulAsset");
        assets[1] = makeAddr("secondSuccessfulAsset");
        assets[2] = makeAddr("thirdSuccessfulAsset");
        target.setAssets(assets);

        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), assets.length, "claim calls");
        for (uint256 i; i < assets.length; ++i) {
            assertEq(target.claimedAssets(i), assets[i], "claim order");
        }
        assertEq(target.lastClaimedAsset(), assets[assets.length - 1], "last claimed asset");
        assertEq(claimer.nextAssetIndex(), 0, "cursor wraps");
        assertEq(vm.getRecordedLogs().length, 0, "claimer event count");
    }

    // Scenarios: BLYC-EXECUTE-P01.
    function test_givenSelectedCursor_executesInCircularOrder() public {
        address[] memory assets = new address[](3);
        assets[0] = makeAddr("circularFirstAsset");
        assets[1] = makeAddr("circularSecondAsset");
        assets[2] = makeAddr("circularThirdAsset");
        target.setAssets(assets);
        vm.prank(admin);
        claimer.setNextAssetIndex(1);

        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimedAssets(0), assets[1], "selected asset claimed first");
        assertEq(target.claimedAssets(1), assets[2], "following asset claimed second");
        assertEq(target.claimedAssets(2), assets[0], "traversal wraps to first asset");
        assertEq(claimer.nextAssetIndex(), 1, "full traversal returns to selected cursor");
    }

    // Scenarios: BLYC-EXECUTE-P01.
    function test_givenCursorOutOfRangeAfterRegistryShrink_normalizesTraversal() public {
        address[] memory initialAssets = new address[](3);
        initialAssets[0] = makeAddr("initialFirstAsset");
        initialAssets[1] = makeAddr("remainingFirstAsset");
        initialAssets[2] = makeAddr("remainingSecondAsset");
        target.setAssets(initialAssets);
        vm.prank(admin);
        claimer.setNextAssetIndex(2);

        address[] memory remainingAssets = new address[](2);
        remainingAssets[0] = initialAssets[1];
        remainingAssets[1] = initialAssets[2];
        target.setAssets(remainingAssets);

        vm.prank(heart);
        claimer.execute();

        assertEq(
            target.claimedAssets(0),
            remainingAssets[0],
            "normalized traversal starts at zero"
        );
        assertEq(
            target.claimedAssets(1),
            remainingAssets[1],
            "normalized traversal visits later asset"
        );
        assertEq(claimer.nextAssetIndex(), 0, "normalized traversal wraps");
    }

    // Scenarios: BLYC-EXECUTE-L05, BLYC-EXECUTE-L06, BLYC-EXECUTE-L07, BLYC-EXECUTE-L08.
    function test_givenDisabled_isNoOpBeforeRegistryRead(
        bool targetActive_,
        bool targetEnabled_
    ) public givenDisabled givenAssetViewReverts {
        _setTargetLifecycle(targetActive_, targetEnabled_);
        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
        assertEq(vm.getRecordedLogs().length, 0, "claimer event count");
    }

    // Scenarios: BLYC-EXECUTE-L09, BLYC-EXECUTE-L10, BLYC-EXECUTE-L11, BLYC-EXECUTE-L12, BLYC-EXECUTE-L13, BLYC-EXECUTE-L14, BLYC-EXECUTE-L15, BLYC-EXECUTE-L16.
    function test_givenTaskInactive_whenExecuted_reverts(
        bool enabled_,
        bool targetActive_,
        bool targetEnabled_
    ) public {
        if (!enabled_) {
            vm.prank(_emergency);
            claimer.disable("");
        }
        _setTargetLifecycle(targetActive_, targetEnabled_);
        target.setAssetViewReverts(true);
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(claimer));

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(claimer)
            )
        );
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "inactive task makes no claim");
        assertEq(claimer.nextAssetIndex(), 0, "inactive task preserves cursor");
        assertEq(vm.getRecordedLogs().length, 0, "inactive task emits no event");
    }

    // Scenarios: BLYC-EXECUTE-L02.
    function test_givenBurnerLoansDisabled_executeDoesNotQueryRegistry() public {
        target.disable("");
        target.setAssetViewReverts(true);

        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "disabled Burner Loans makes no claim");
        assertEq(claimer.nextAssetIndex(), 0, "disabled Burner Loans preserves cursor");
        assertEq(vm.getRecordedLogs().length, 0, "disabled Burner Loans emits no task event");
    }

    // Scenarios: BLYC-EXECUTE-L03, BLYC-EXECUTE-L04.
    function test_givenBurnerLoansInactive_executeDoesNotQueryRegistry(bool enabled_) public {
        if (!enabled_) target.disable("");
        target.setAssetViewReverts(true);
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(target));

        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "inactive Burner Loans makes no claim");
        assertEq(claimer.nextAssetIndex(), 0, "inactive Burner Loans preserves cursor");
        assertEq(vm.getRecordedLogs().length, 0, "inactive Burner Loans emits no task event");
    }

    // Scenarios: BLYC-EXECUTE-A01.
    function test_givenDisabled_whenCallerWithoutHeartRole_reverts(
        address caller_,
        bool targetActive_,
        bool targetEnabled_
    ) public givenDisabled {
        vm.assume(caller_ != heart);
        _setTargetLifecycle(targetActive_, targetEnabled_);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE));
        vm.prank(caller_);
        claimer.execute();
    }

    // Scenarios: BLYC-EXECUTE-P02, BLYC-SELF-EXECUTE-P03.
    function test_givenClaimReverts_reportsFailure() public {
        target.setClaimReverts(true);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.YieldAssetClaimFailed(
            target.getAssetAt(0),
            MockBurnerLoansYieldClaimerTaskTarget.ClaimReverted.selector
        );
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
        assertEq(claimer.nextAssetIndex(), 0, "single-asset cursor wraps after failed attempt");
    }

    // Scenarios: BLYC-EXECUTE-P02.
    function test_givenClaimRevertsWithLessThanSelector_reportsAvailablePrefix() public {
        target.setClaimRevertsWithShortData(true);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.YieldAssetClaimFailed(
            target.getAssetAt(0),
            bytes4(0xab00_0000)
        );
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    // Scenarios: BLYC-EXECUTE-P02.
    function test_givenClaimRevertsWithLargeData_reportsBoundedFailure() public {
        target.setClaimRevertsWithLargeData(true);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.YieldAssetClaimFailed(target.getAssetAt(0), bytes4(0));
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    // Scenarios: BLYC-SELF-EXECUTE-P02.
    function test_givenAttemptThresholdExceedsAvailableGas_pausesBeforeLookup()
        public
        givenExecutionGasLimit(type(uint32).max)
    {
        address[] memory assets = new address[](2);
        assets[0] = makeAddr("firstAvailableGasAsset");
        assets[1] = makeAddr("secondAvailableGasAsset");
        target.setAssets(assets);
        vm.prank(admin);
        claimer.setMinimumGasToAttempt(type(uint32).max);
        vm.recordLogs();
        vm.prank(heart);
        claimer.execute{gas: 200_000}();

        assertEq(target.claimCalls(), 0, "claim calls");
        assertEq(claimer.nextAssetIndex(), 0, "cursor does not advance without an attempt");
        assertEq(vm.getRecordedLogs().length, 0, "no task event");
    }

    // Scenarios: BLYC-SELF-EXECUTE-P02.
    function test_givenPostLookupGasCannotPreserveReserve_pausesBeforeCursorAdvance() public {
        address[] memory assets = new address[](2);
        assets[0] = makeAddr("firstReserveBoundAsset");
        assets[1] = makeAddr("secondReserveBoundAsset");
        target.setAssets(assets);
        vm.startPrank(admin);
        claimer.setGasReserve(240_000);
        claimer.setExecutionGasLimit(300_000);
        vm.stopPrank();

        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
        assertEq(claimer.nextAssetIndex(), 0, "unattempted asset remains next");
        assertEq(vm.getRecordedLogs().length, 0, "no task event");
    }

    // Scenarios: BLYC-EXECUTE-P02, BLYC-SELF-EXECUTE-P03.
    function test_givenClaimExhaustsGas_laterHeartTaskStillExecutes() public {
        MockPeriodicTaskManager taskManager = new MockPeriodicTaskManager(kernel);
        MockPeriodicTask laterTask = new MockPeriodicTask();
        address[] memory assets = new address[](2);
        assets[0] = makeAddr("firstExhaustingAsset");
        assets[1] = makeAddr("secondExhaustingAsset");
        target.setAssets(assets);
        target.setClaimConsumesAllGasAsset(assets[0]);

        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(taskManager));
        rolesAdmin.grantRole(HEART_ROLE, address(taskManager));
        claimer.setExecutionGasLimit(500_000);
        taskManager.addPeriodicTask(address(claimer));
        taskManager.addPeriodicTask(address(laterTask));
        vm.stopPrank();

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.YieldAssetClaimFailed(assets[0], bytes4(0));
        taskManager.executeAllTasks{gas: 1_000_000}();

        assertEq(laterTask.count(), 1, "later task count");
        assertEq(target.claimCalls(), 0, "claim calls");
        assertEq(claimer.nextAssetIndex(), 1, "cursor advances past gas-burning asset");
    }

    // Scenarios: BLYC-EXECUTE-P02, BLYC-SELF-EXECUTE-P03, BLYC-SELF-EXECUTE-P04.
    function test_givenLaterClaimExhaustsGas_preservesProgressAndResumes()
        public
        givenExecutionGasLimit(500_000)
    {
        address[] memory assets = new address[](3);
        assets[0] = makeAddr("firstAsset");
        assets[1] = makeAddr("secondAsset");
        assets[2] = makeAddr("thirdAsset");
        target.setAssets(assets);
        target.setClaimConsumesAllGasAsset(assets[1]);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.YieldAssetClaimFailed(assets[1], bytes4(0));
        vm.prank(heart);
        claimer.execute{gas: 1_000_000}();

        assertEq(target.claimCalls(), 1, "earlier claim remains committed");
        assertEq(target.lastClaimedAsset(), assets[0], "earlier claimed asset");
        assertEq(claimer.nextAssetIndex(), 2, "cursor advances past gas-burning asset");

        vm.prank(heart);
        claimer.execute{gas: 1_000_000}();

        assertEq(target.claimCalls(), 3, "later assets progress on next beat");
        assertEq(target.claimedAssets(1), assets[2], "next beat starts after failed asset");
        assertEq(target.claimedAssets(2), assets[0], "next beat wraps after later asset");
        assertEq(claimer.nextAssetIndex(), 2, "cursor again advances past gas-burning asset");
    }

    // Scenarios: BLYC-EXECUTE-P03.
    function test_givenMinimumTaskGasLimit_reportsExecutionFailure()
        public
        givenExecutionGasLimit(1)
    {
        address[] memory assets = new address[](2);
        assets[0] = makeAddr("firstMinimumBudgetAsset");
        assets[1] = makeAddr("secondMinimumBudgetAsset");
        target.setAssets(assets);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.ExecutionFailed(bytes4(0));
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
        assertEq(claimer.nextAssetIndex(), 0, "failed self-call preserves cursor");
    }

    // Scenarios: BLYC-SELF-EXECUTE-A02, BLYC-SELF-EXECUTE-I01.
    function test_givenNoRegisteredAssets_isNoOp() public {
        target.setAssets(new address[](0));

        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
        assertEq(claimer.nextAssetIndex(), 0, "empty registry preserves cursor");
        assertEq(vm.getRecordedLogs().length, 0, "claimer event count");
    }

    // Scenarios: BLYC-SELF-EXECUTE-P04.
    function test_givenLimitedExecutionGas_repeatedBeatsReachEveryAsset() public {
        address[] memory assets = new address[](8);
        for (uint256 i; i < assets.length; ++i) {
            assets[i] = address(uint160(i + 1));
        }
        target.setAssets(assets);
        vm.prank(admin);
        // Include the modular Core metadata/accounting reads and a cold successful settlement,
        // while keeping the self-call budget below a complete eight-asset traversal.
        claimer.setExecutionGasLimit(400_000);

        for (uint256 beat; beat < assets.length; ++beat) {
            vm.prank(heart);
            claimer.execute();
        }

        for (uint256 i; i < assets.length; ++i) {
            bool claimed;
            for (uint256 j; j < target.claimCalls(); ++j) {
                if (target.claimedAssets(j) == assets[i]) claimed = true;
            }
            assertTrue(claimed, "every asset eventually claimed");
        }
    }

    // Scenarios: BLYC-EXECUTE-P03.
    function test_givenAssetRegistryReadReverts_reportsExecutionFailure()
        public
        givenAssetViewReverts
    {
        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.ExecutionFailed(
            MockBurnerLoansYieldClaimerTaskTarget.AssetViewReverted.selector
        );
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
        assertEq(claimer.nextAssetIndex(), 0, "failed count read preserves cursor");
    }

    // Scenarios: BLYC-EXECUTE-P03, BLYC-SELF-EXECUTE-P01.
    function test_givenLaterAssetReadReverts_rollsBackEarlierClaimAndCursor() public {
        address[] memory assets = new address[](2);
        assets[0] = makeAddr("firstReadAsset");
        assets[1] = makeAddr("revertingReadAsset");
        target.setAssets(assets);
        target.setAssetViewRevertIndex(1);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.ExecutionFailed(
            MockBurnerLoansYieldClaimerTaskTarget.AssetViewReverted.selector
        );
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "earlier claim rolls back");
        assertEq(claimer.nextAssetIndex(), 0, "earlier cursor advance rolls back");
    }

    // Scenarios: BLYC-EXECUTE-P03.
    function test_givenSelfTaskShortError_whenExecuted() public {
        vm.mockCallRevert(address(claimer), abi.encodeCall(claimer.selfExecuteTask, ()), hex"ab");
        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.ExecutionFailed(bytes4(0xab000000));
        vm.prank(heart);
        claimer.execute();
        assertEq(target.claimCalls(), 0, "Self failure makes no claims");
    }

    // Scenarios: BLYC-EXECUTE-P03.
    function test_givenSelfTaskLargeError_whenExecuted() public {
        bytes memory reason = new bytes(100_000);
        reason[0] = 0xab;
        reason[1] = 0xcd;
        vm.mockCallRevert(address(claimer), abi.encodeCall(claimer.selfExecuteTask, ()), reason);
        vm.expectEmit(false, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimerTask.ExecutionFailed(bytes4(0xabcd0000));
        vm.prank(heart);
        claimer.execute();
        assertEq(target.claimCalls(), 0, "Bounded prefix retains outer execution");
    }

    // Scenarios: BLYC-EXECUTE-P02, BLYC-SELF-EXECUTE-P03, BLYC-SELF-EXECUTE-P04.
    function test_givenGasBurnerAtLastAsset_whenRepeatedBeatsExecute() public {
        address[] memory assets = new address[](3);
        assets[0] = address(1);
        assets[1] = address(2);
        assets[2] = address(3);
        target.setAssets(assets);
        target.setClaimConsumesAllGasAsset(assets[2]);
        vm.prank(admin);
        claimer.setExecutionGasLimit(600_000);
        for (uint256 beat; beat < 3; ++beat) {
            vm.prank(heart);
            claimer.execute{gas: 1_000_000}();
            assertEq(target.claimCalls(), 2 * (beat + 1), "Healthy assets progress once per beat");
            assertEq(claimer.nextAssetIndex(), 0, "Failing final asset rotates to start");
        }
    }

    // Scenarios: BLYC-EXECUTE-L09, BLYC-EXECUTE-L13.
    function test_givenInactive_whenUnauthorizedAndInvalid_reverts(
        address caller_,
        bool enabled_
    ) public {
        vm.assume(caller_ != heart);
        if (!enabled_) {
            vm.prank(_emergency);
            claimer.disable("");
        }
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(claimer));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(claimer)
            )
        );
        vm.prank(caller_);
        claimer.execute();
    }
}

// forge-lint: disable-end(unsafe-typecast)

// forge-lint: disable-end(calls-loop)

// forge-lint: disable-end(literal-instead-of-constant)
