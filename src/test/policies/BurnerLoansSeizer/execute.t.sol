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

    function test_givenSeizableBorrowers_scansAdvancesAndSeizes() public {
        target.setScanResult(assetOne, _single(alice), 3, 0);

        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetOne), 3, "asset cursor");
        assertEq(target.seizureCalls(), 1, "seizure calls");
        assertEq(target.lastSeizedAsset(), assetOne, "seized asset");
        assertEq(target.getLastSeizedBorrowers(), _single(alice), "seized borrowers");
    }

    function test_givenNoManagedAssets_returnsWithoutCallingTarget() public {
        vm.prank(admin);
        seizer.removeAsset(assetOne);

        vm.prank(heart);
        seizer.execute();

        assertEq(target.seizureCalls(), 0, "seizure calls");
        assertEq(seizer.nextAssetIndex(), 0, "next asset index");
    }

    function test_givenNoSeizableBorrowers_advancesCursorWithoutSeizing() public {
        target.setScanResult(assetOne, new address[](0), 4, 0);

        vm.prank(heart);
        seizer.execute();

        assertEq(seizer.assetCursor(assetOne), 4, "asset cursor");
        assertEq(target.seizureCalls(), 0, "seizure calls");
    }

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
    }

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

    function test_givenCallerWithoutHeartRole_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, HEART_ROLE));
        seizer.execute();
    }

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
