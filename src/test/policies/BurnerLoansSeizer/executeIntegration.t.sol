// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions, Module} from "src/Kernel.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansSeizureTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansSeizureTestBase.sol";

contract BurnerLoansSeizerExecuteIntegrationTest is BurnerLoansSeizureTestBase {
    BurnerLoansSeizer internal seizer;
    address internal heart;

    function setUp() public override {
        super.setUp();
        heart = makeAddr("heart");

        vm.startPrank(admin);
        seizer = new BurnerLoansSeizer(kernel, address(burnerLoans), 10, 5, 10_000_000);
        kernel.executeAction(Actions.ActivatePolicy, address(seizer));
        rolesAdmin.grantRole(HEART_ROLE, heart);
        rolesAdmin.grantRole(BURNER_LOANS_SEIZER_ROLE, address(seizer));
        seizer.addAsset(address(usds));
        vm.stopPrank();
    }

    // execute
    // given matured position
    //  when execute is called through the Heart role
    //   then it seizes without keeper reward
    function test_givenMaturedPosition_seizesWithoutKeeperReward() public {
        _makeMatured(alice);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        uint256 expectedApproval = burnerLoans.globalDebtCapOhm();

        vm.expectEmit(false, false, false, true, address(burnerLoans));
        emit IBurnerLoans.MintApprovalSynchronized(expectedApproval);
        vm.expectEmit(false, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.MintApprovalSynchronized(expectedApproval);

        vm.prank(heart);
        seizer.execute();

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 0, "position debt");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            0,
            "position collateral"
        );
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "global active debt");
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), 0, "asset active debt");
        assertEq(usds.balanceOf(address(seizer)), 0, "seizer reward balance");
        assertEq(usds.balanceOf(address(trsry)), treasuryBefore + 2_000e18, "treasury collateral");
        assertEq(mintr.mintApproval(address(burnerLoans)), expectedApproval, "mint approval");
    }

    // execute
    // given no borrower is seizable and MINTR approval is below unused capacity
    //  when execute is called through the Heart role
    //   then it reconciles approval without seizing
    function test_givenNoSeizableBorrowers_reconcilesMintApproval() public {
        uint256 expectedApproval = burnerLoans.globalDebtCapOhm();
        vm.prank(address(burnerLoans));
        mintr.decreaseMintApproval(address(burnerLoans), 1);

        vm.prank(heart);
        seizer.execute();

        assertEq(mintr.mintApproval(address(burnerLoans)), expectedApproval, "mint approval");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt");
    }

    // execute
    // given no assets are managed and MINTR approval is below unused capacity
    //  when execute is called through the Heart role
    //   then it still reconciles approval
    function test_givenNoManagedAssets_reconcilesMintApproval() public {
        vm.prank(admin);
        seizer.removeAsset(address(usds));
        uint256 expectedApproval = burnerLoans.globalDebtCapOhm();
        vm.prank(address(burnerLoans));
        mintr.decreaseMintApproval(address(burnerLoans), 1);

        vm.prank(heart);
        seizer.execute();

        assertEq(mintr.mintApproval(address(burnerLoans)), expectedApproval, "mint approval");
    }

    // execute
    // given Burner Loans cannot update MINTR approval
    //  when execute is called through the Heart role
    //   then it reports the sync failure without reverting
    function test_givenMintApprovalPermissionMissing_reportsFailureWithoutReverting() public {
        uint256 expectedUnchangedApproval = burnerLoans.globalDebtCapOhm() - 1;
        vm.prank(address(burnerLoans));
        mintr.decreaseMintApproval(address(burnerLoans), 1);

        vm.startPrank(admin);
        seizer.removeAsset(address(usds));
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        vm.stopPrank();

        vm.expectEmit(false, false, false, true, address(seizer));
        emit IBurnerLoansSeizer.MintApprovalSyncFailed(Module.Module_PolicyNotPermitted.selector);
        vm.prank(heart);
        seizer.execute();

        assertEq(
            mintr.mintApproval(address(burnerLoans)),
            expectedUnchangedApproval,
            "approval unchanged"
        );
    }
}
