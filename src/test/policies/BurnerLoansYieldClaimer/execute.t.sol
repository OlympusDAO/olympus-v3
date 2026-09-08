// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";
import {MockBurnerLoansYieldClaimerTarget} from "./MockBurnerLoansYieldClaimerTarget.sol";

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.
// forge-lint: disable-start(unsafe-typecast)

contract BurnerLoansYieldClaimerExecuteTest is BurnerLoansYieldClaimerTest {
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

    function test_givenCallerWithoutHeartRole_reverts(address caller_) public {
        vm.assume(caller_ != heart);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE));
        vm.prank(caller_);
        claimer.execute();
    }

    function test_givenClaimSucceeds_callsBurnerLoans() public {
        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 1, "claim calls");
        assertEq(target.lastClaimedAsset(), target.getAssetAt(0), "claimed asset");
        assertEq(vm.getRecordedLogs().length, 0, "claimer event count");
    }

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
        assertEq(target.lastClaimedAsset(), assets[assets.length - 1], "last claimed asset");
        assertEq(vm.getRecordedLogs().length, 0, "claimer event count");
    }

    function test_givenDisabled_isNoOpBeforeRegistryRead()
        public
        givenDisabled
        givenAssetViewReverts
    {
        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
        assertEq(vm.getRecordedLogs().length, 0, "claimer event count");
    }

    function test_givenDisabled_whenCallerWithoutHeartRole_reverts(
        address caller_
    ) public givenDisabled {
        vm.assume(caller_ != heart);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE));
        vm.prank(caller_);
        claimer.execute();
    }

    function test_givenClaimReverts_reportsFailure() public {
        target.setClaimReverts(true);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.YieldAssetClaimFailed(
            target.getAssetAt(0),
            MockBurnerLoansYieldClaimerTarget.ClaimReverted.selector
        );
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    function test_givenClaimRevertsWithLessThanSelector_reportsAvailablePrefix() public {
        target.setClaimRevertsWithShortData(true);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.YieldAssetClaimFailed(
            target.getAssetAt(0),
            bytes4(0xab00_0000)
        );
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    function test_givenClaimRevertsWithLargeData_reportsBoundedFailure() public {
        target.setClaimRevertsWithLargeData(true);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.YieldAssetClaimFailed(target.getAssetAt(0), bytes4(0));
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    function test_givenConfiguredGasExceedsAvailableGas_reportsFailure()
        public
        givenExecutionGasLimit(type(uint32).max)
    {
        address[] memory assets = new address[](2);
        assets[0] = makeAddr("firstAvailableGasAsset");
        assets[1] = makeAddr("secondAvailableGasAsset");
        target.setAssets(assets);
        target.setClaimConsumesAllGasAsset(assets[0]);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.ExecutionFailed(bytes4(0));
        vm.prank(heart);
        claimer.execute{gas: 200_000}();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

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
        claimer.setExecutionGasLimit(200_000);
        taskManager.addPeriodicTask(address(claimer));
        taskManager.addPeriodicTask(address(laterTask));
        vm.stopPrank();

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.ExecutionFailed(bytes4(0));
        taskManager.executeAllTasks{gas: 1_000_000}();

        assertEq(laterTask.count(), 1, "later task count");
        assertEq(target.claimCalls(), 0, "claim calls");
    }

    function test_givenLaterClaimExhaustsTaskGas_rollsBackEarlierClaim()
        public
        givenExecutionGasLimit(200_000)
    {
        address[] memory assets = new address[](3);
        assets[0] = makeAddr("firstAsset");
        assets[1] = makeAddr("secondAsset");
        assets[2] = makeAddr("thirdAsset");
        target.setAssets(assets);
        target.setClaimConsumesAllGasAsset(assets[1]);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.ExecutionFailed(bytes4(0));
        vm.prank(heart);
        claimer.execute{gas: 1_000_000}();

        assertEq(target.claimCalls(), 0, "claim calls");
        assertEq(target.lastClaimedAsset(), address(0), "last claimed asset");
    }

    function test_givenMinimumTaskGasLimit_reportsExecutionFailure()
        public
        givenExecutionGasLimit(1)
    {
        address[] memory assets = new address[](2);
        assets[0] = makeAddr("firstMinimumBudgetAsset");
        assets[1] = makeAddr("secondMinimumBudgetAsset");
        target.setAssets(assets);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.ExecutionFailed(bytes4(0));
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    function test_givenNoRegisteredAssets_isNoOp() public {
        target.setAssets(new address[](0));

        vm.recordLogs();
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
        assertEq(vm.getRecordedLogs().length, 0, "claimer event count");
    }

    function test_givenRegistryExceedsTaskGasLimit_reportsSingleExecutionFailure()
        public
        givenExecutionGasLimit(200_000)
    {
        address[] memory assets = new address[](100);
        for (uint256 i; i < assets.length; ++i) {
            assets[i] = address(uint160(i + 1));
        }
        target.setAssets(assets);

        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.ExecutionFailed(bytes4(0));
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    function test_givenAssetRegistryReadReverts_reportsExecutionFailure()
        public
        givenAssetViewReverts
    {
        vm.expectEmit(true, false, false, true, address(claimer));
        emit IBurnerLoansYieldClaimer.ExecutionFailed(
            MockBurnerLoansYieldClaimerTarget.AssetViewReverted.selector
        );
        vm.prank(heart);
        claimer.execute();

        assertEq(target.claimCalls(), 0, "claim calls");
    }

    function test_givenCallerIsNotSelf_selfExecuteTaskReverts(address caller_) public {
        vm.assume(caller_ != address(claimer));

        vm.expectRevert(IBurnerLoansYieldClaimer.BurnerLoansYieldClaimer_OnlySelf.selector);
        vm.prank(caller_);
        claimer.selfExecuteTask();
    }
}

// forge-lint: disable-end(unsafe-typecast)

// forge-lint: disable-end(literal-instead-of-constant)
