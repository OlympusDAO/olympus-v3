// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BurnerLoansBorrowTestBase} from "../BurnerLoans/fixtures/BurnerLoansBorrowTestBase.sol";

contract RevenueDistributorTaskBurnerLoansSeparationTest is BurnerLoansBorrowTestBase {
    uint128 internal constant COLLATERAL_AMOUNT = 2_000e18;
    uint128 internal constant BORROW_AMOUNT = 100e9;
    uint256 internal constant DISTRIBUTOR_RECEIPT = 7;

    // Scenarios: TASK-P06.
    function test_givenBurnerLoansPendingFee_taskSettlesOnlyDistributorCustody(
        bool burnerLoansActive_
    ) public {
        usds.mint(alice, COLLATERAL_AMOUNT + 100e18);
        vm.startPrank(alice);
        assertTrue(
            usds.approve(address(burnerLoans), type(uint256).max),
            "collateral approval succeeds"
        );
        (
            uint256 depositedAmount,
            uint256 resultingCollateral,
            uint256 depositHealthFactor
        ) = burnerLoans.depositCollateral(address(usds), COLLATERAL_AMOUNT, alice);
        vm.stopPrank();
        assertEq(depositedAmount, COLLATERAL_AMOUNT, "collateral deposit succeeds");
        assertEq(resultingCollateral, COLLATERAL_AMOUNT, "position collateral matches deposit");
        assertGt(depositHealthFactor, 0, "deposit health factor is positive");

        RevenueDistributor distributor = _installFeeDistributorForTest(address(usds));
        uint256 fee = burnerLoans.previewBorrow(address(usds), BORROW_AMOUNT, alice).fee;
        vm.mockCallRevert(
            address(usds),
            abi.encodeWithSelector(usds.transfer.selector, address(distributor)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        vm.prank(alice);
        (
            uint256 borrowed,
            uint256 chargedFee,
            uint256 resultingDebt,
            uint48 maturity,
            uint256 borrowHealthFactor
        ) = burnerLoans.borrow(address(usds), BORROW_AMOUNT, alice, alice, fee);
        assertEq(borrowed, BORROW_AMOUNT, "borrow principal matches request");
        assertEq(chargedFee, fee, "borrow fee matches preview");
        assertGt(resultingDebt, 0, "borrow creates debt");
        assertGt(maturity, block.timestamp, "borrow maturity is in the future");
        assertGt(borrowHealthFactor, 0, "borrow health factor is positive");
        vm.clearMockedCalls();
        if (!burnerLoansActive_) _deactivatePolicy(address(burnerLoans));

        address heart = makeAddr("revenue distributor heart");
        vm.startPrank(admin);
        RevenueDistributorTask task = new RevenueDistributorTask(
            kernel,
            address(distributor),
            5_000_000
        );
        kernel.executeAction(Actions.ActivatePolicy, address(task));
        rolesAdmin.grantRole(HEART_ROLE, heart);
        task.enable("");
        vm.stopPrank();
        usds.mint(address(distributor), DISTRIBUTOR_RECEIPT);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.prank(heart);
        task.execute();

        assertEq(
            usds.balanceOf(address(trsry)) - treasuryBefore,
            DISTRIBUTOR_RECEIPT,
            "RD custody settles"
        );
        assertEq(
            burnerLoans.pendingFeeForTest(address(usds)),
            fee,
            "Burner Loans fee bucket unchanged"
        );
        assertEq(
            burnerLoans.pendingPayout(address(usds), address(distributor)),
            fee,
            "fee remains owed to distributor"
        );

        if (!burnerLoansActive_) _activatePolicy(address(burnerLoans));
        uint256 transferred = burnerLoans.transferPendingPayout(
            address(usds),
            address(distributor)
        );
        assertEq(transferred, fee, "direct retry transfers pending fee");
        vm.prank(heart);
        task.execute();
        assertEq(
            usds.balanceOf(address(trsry)) - treasuryBefore,
            DISTRIBUTOR_RECEIPT + fee,
            "direct retry then task settles fee once"
        );
        assertEq(burnerLoans.pendingFeeForTest(address(usds)), 0, "fee bucket clears once");
    }
}
