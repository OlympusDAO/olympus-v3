// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockPeriodicTask} from "src/test/bases/PeriodicTaskManager/MockPeriodicTask.sol";
import {MockPeriodicTaskManager} from "src/test/bases/PeriodicTaskManager/MockPeriodicTaskManager.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";
import {MockBurnerLoansSeizerTarget} from "./MockBurnerLoansSeizerTarget.sol";

contract BurnerLoansSeizerExecuteTest is BurnerLoansSeizerTest {
    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        seizer.addAsset(assetOne);
    }

    // execute
    // given seizable borrowers
    //  when execute is called
    //   then it scans advances and seizes
    function test_givenSeizableBorrowers_scansAdvancesAndSeizes() public {
        target.setScanResult(assetOne, _single(alice), 3, 0);
        target.setSyncApproval(77);

        vm.expectEmit(false, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.MintApprovalSynchronized(77);

        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetOne), 3, "asset cursor");
        assertEq(target.seizureCalls(), 1, "seizure calls");
        assertEq(target.lastSeizedAsset(), assetOne, "seized asset");
        assertEq(target.getLastSeizedBorrowers(), _single(alice), "seized borrowers");
        assertEq(target.syncCalls(), 1, "sync calls");
    }

    // execute
    // given no managed assets
    //  when execute is called
    //   then it still synchronizes mint approval
    function test_givenNoManagedAssets_synchronizesMintApproval() public {
        vm.prank(admin);
        seizer.removeAsset(assetOne);
        target.setSyncApproval(88);

        vm.prank(heart);
        seizer.execute();

        assertEq(target.seizureCalls(), 0, "seizure calls");
        assertEq(target.syncCalls(), 1, "sync calls");
        assertEq(seizer.nextAssetIndex(), 0, "next asset index");
    }

    // execute
    // given no seizable borrowers
    //  when execute is called
    //   then it advances cursor without seizing
    function test_givenNoSeizableBorrowers_advancesCursorWithoutSeizing() public {
        target.setScanResult(assetOne, new address[](0), 4, 0);

        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetOne), 4, "asset cursor");
        assertEq(target.seizureCalls(), 0, "seizure calls");
        assertEq(target.syncCalls(), 1, "sync calls");
    }

    // execute
    // given multiple assets
    //  when execute is called
    //   then it processes one asset per execution
    function test_givenMultipleAssets_processesOneAssetPerExecution() public {
        vm.prank(admin);
        seizer.addAsset(assetTwo);
        target.setScanResult(assetOne, new address[](0), 1, 0);
        target.setScanResult(assetTwo, _single(alice), 2, 0);

        vm.prank(heart);
        seizer.execute();
        assertEq(seizer.assetCursor(assetOne), 1, "first asset cursor");
        assertEq(seizer.assetCursor(assetTwo), 0, "second asset cursor before execution");

        vm.prank(heart);
        seizer.execute();
        assertEq(seizer.assetCursor(assetTwo), 2, "second asset cursor");
        assertEq(target.lastSeizedAsset(), assetTwo, "seized asset");
    }

    // execute
    // given seizure reverts
    //  when execute is called
    //   then it does not advance borrower cursor
    function test_givenSeizureReverts_doesNotAdvanceBorrowerCursor() public {
        vm.prank(admin);
        seizer.addAsset(assetTwo);
        target.setScanResult(assetOne, _single(alice), 3, 0);
        target.setSeizureReverts(true);

        vm.expectEmit(true, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.SeizureFailed(
            assetOne,
            MockBurnerLoansSeizerTarget.SeizureReverted.selector
        );
        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetOne), 0, "failed asset cursor");
        assertEq(seizer.nextAssetIndex(), 1, "next asset index");
        assertEq(target.syncCalls(), 1, "sync after failed seizure");

        target.setSeizureReverts(false);
        target.setScanResult(assetTwo, _single(alice), 4, 0);
        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetTwo), 4, "next asset cursor");
        assertEq(target.lastSeizedAsset(), assetTwo, "next seized asset");
        assertEq(target.syncCalls(), 2, "sync after successful retry");
    }

    // execute
    // given scan reverts
    //  when execute is called
    //   then it advances to next asset without changing cursor
    function test_givenScanReverts_advancesToNextAssetWithoutChangingCursor() public {
        vm.prank(admin);
        seizer.addAsset(assetTwo);
        target.setScanReverts(true);

        vm.expectEmit(true, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.ScanFailed(
            assetOne,
            MockBurnerLoansSeizerTarget.ScanReverted.selector
        );
        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetOne), 0, "failed asset cursor");
        assertEq(seizer.nextAssetIndex(), 1, "next asset index");
        assertEq(target.syncCalls(), 1, "sync after failed scan");
    }

    // execute
    // given caller without heart role
    //  when execute is called
    //   then it reverts
    function test_givenCallerWithoutHeartRole_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE));
        seizer.execute();
    }

    // execute
    // given seizer role missing
    //  when execute is called
    //   then it does not scan or seize
    function test_givenSeizerRoleMissing_doesNotScanOrSeize() public {
        vm.prank(admin);
        rolesAdmin.revokeRole(BURNER_LOANS_SEIZER_ROLE, address(seizer));
        target.setScanResult(assetOne, _single(alice), 3, 100);
        target.setSyncReverts(true);

        vm.expectEmit(true, false, false, false, address(seizer));
        emit IBurnerLoansSeizer.SeizerRoleMissing(assetOne);
        vm.expectEmit(false, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.MintApprovalSyncFailed(
            MockBurnerLoansSeizerTarget.SyncReverted.selector
        );
        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetOne), 0, "asset cursor");
        assertEq(target.seizureCalls(), 0, "seizure calls");
        assertEq(target.syncCalls(), 0, "successful sync calls");
    }

    // execute
    // given mint approval synchronization reverts
    //  when execute is called
    //   then it reports the failure without reverting
    function test_givenMintApprovalSyncReverts_reportsFailureWithoutReverting() public {
        target.setScanResult(assetOne, new address[](0), 2, 0);
        target.setSyncReverts(true);

        vm.expectEmit(false, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.MintApprovalSyncFailed(
            MockBurnerLoansSeizerTarget.SyncReverted.selector
        );
        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetOne), 2, "asset cursor");
        assertEq(target.syncCalls(), 0, "successful sync calls");
    }

    // execute
    // given mint approval synchronization reverts and another Heart task follows the seizer
    //  when the periodic task manager executes all tasks
    //   then the later task still executes
    function test_givenMintApprovalSyncReverts_laterHeartTaskStillExecutes() public {
        MockPeriodicTaskManager taskManager = new MockPeriodicTaskManager(kernel);
        MockPeriodicTask laterTask = new MockPeriodicTask();
        target.setSyncReverts(true);

        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(taskManager));
        rolesAdmin.grantRole(HEART_ROLE, address(taskManager));
        taskManager.addPeriodicTask(address(seizer));
        taskManager.addPeriodicTask(address(laterTask));
        vm.stopPrank();

        taskManager.executeAllTasks();

        assertEq(laterTask.count(), 1, "later task count");
    }

    // execute
    // given Burner Loans exhausts the gas allocated to the seizer task
    //  when the periodic task manager executes all tasks
    //   then the seizer returns without blocking the later task
    function test_givenTargetExhaustsGas_laterHeartTaskStillExecutes() public {
        MockPeriodicTaskManager taskManager = new MockPeriodicTaskManager(kernel);
        MockPeriodicTask laterTask = new MockPeriodicTask();
        target.setScanConsumesAllGas(true);

        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(taskManager));
        rolesAdmin.grantRole(HEART_ROLE, address(taskManager));
        seizer.setExecutionGasLimit(200_000);
        taskManager.addPeriodicTask(address(seizer));
        taskManager.addPeriodicTask(address(laterTask));
        vm.stopPrank();

        vm.expectEmit(false, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.ExecutionFailed(bytes4(0));
        taskManager.executeAllTasks{gas: 1_000_000}();

        assertEq(laterTask.count(), 1, "later task count");
        assertEq(target.syncCalls(), 0, "sync calls");
        assertEq(seizer.nextAssetIndex(), 0, "next asset index");
    }

    // selfExecuteTask
    // given a caller other than the seizer itself
    //  when the inner task entry point is called
    //   then it reverts
    function test_givenCallerIsNotSelf_selfExecuteTaskReverts() public {
        vm.expectRevert(IBurnerLoansSeizer.BurnerLoansSeizer_OnlySelf.selector);
        seizer.selfExecuteTask();
    }

    // execute
    // given cursor at end
    //  when execute is called
    //   then it wraps to zero
    function test_givenCursorAtEnd_wrapsToZero() public {
        target.setScanResult(assetOne, new address[](0), 4, 0);
        vm.prank(heart);
        seizer.execute();
        assertEq(seizer.assetCursor(assetOne), 4, "cursor before wrap");

        target.setScanResult(assetOne, new address[](0), 0, 0);
        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetOne), 0, "wrapped cursor");
    }
}
