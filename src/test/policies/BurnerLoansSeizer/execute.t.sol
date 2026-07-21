// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

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

        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetOne), 3, "asset cursor");
        assertEq(target.seizureCalls(), 1, "seizure calls");
        assertEq(target.lastSeizedAsset(), assetOne, "seized asset");
        assertEq(target.getLastSeizedBorrowers(), _single(alice), "seized borrowers");
    }

    // execute
    // given no managed assets
    //  when execute is called
    //   then it returns without calling target
    function test_givenNoManagedAssets_returnsWithoutCallingTarget() public {
        vm.prank(admin);
        seizer.removeAsset(assetOne);

        vm.prank(heart);
        seizer.execute();

        assertEq(target.seizureCalls(), 0, "seizure calls");
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

        target.setSeizureReverts(false);
        target.setScanResult(assetTwo, _single(alice), 4, 0);
        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetTwo), 4, "next asset cursor");
        assertEq(target.lastSeizedAsset(), assetTwo, "next seized asset");
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

        vm.expectEmit(true, false, false, false, address(seizer));
        emit IBurnerLoansSeizer.SeizerRoleMissing(assetOne);
        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetOne), 0, "asset cursor");
        assertEq(target.seizureCalls(), 0, "seizure calls");
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
