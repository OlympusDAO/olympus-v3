// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
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
        seizer.enable("");
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
        uint256 expectedApproval = inventory.globalDebtCapOhm();

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
        assertEq(inventory.activePrincipalOhm(), 0, "Burner Loans Inventory active principal");
        assertEq(mintr.mintApproval(address(inventory)), expectedApproval, "mint approval");
    }

    // execute
    // given no borrower is seizable and MINTR approval has an unrecorded deficit
    //  when execute is called through the Heart role
    //   then it does not undo the conservative approval reduction
    function test_givenNoSeizableBorrowers_doesNotRestoreUnrecordedDeficit() public {
        uint256 expectedApproval = inventory.globalDebtCapOhm() - 1;
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), 1);

        vm.prank(heart);
        seizer.execute();

        assertEq(mintr.mintApproval(address(inventory)), expectedApproval, "mint approval");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt");
    }

    // execute
    // given no assets are managed and MINTR approval has an unrecorded deficit
    //  when execute is called through the Heart role
    //   then it does not restore the unrecorded deficit
    function test_givenNoManagedAssets_doesNotRestoreUnrecordedDeficit() public {
        vm.prank(admin);
        seizer.removeAsset(address(usds));
        uint256 expectedApproval = inventory.globalDebtCapOhm() - 1;
        vm.prank(address(inventory));
        mintr.decreaseMintApproval(address(inventory), 1);

        vm.prank(heart);
        seizer.execute();

        assertEq(mintr.mintApproval(address(inventory)), expectedApproval, "mint approval");
    }

    // execute
    // given a completed seizure reduces active principal
    //  when Burner Loans Inventory records the default
    //   then it immediately restores full cap-derived capacity
    function test_givenCompletedSeizure_restoresCapacity() public {
        _makeMatured(alice);
        vm.prank(heart);
        seizer.execute();

        assertEq(
            mintr.mintApproval(address(inventory)),
            inventory.desiredMintApproval(),
            "approval restored"
        );
        assertEq(inventory.activePrincipalOhm(), 0, "active principal");
    }
}
