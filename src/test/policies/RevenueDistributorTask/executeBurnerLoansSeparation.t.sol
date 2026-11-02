// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

// Libraries
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, toKeycode} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

contract RevenueDistributorTaskBurnerLoansSeparationTest is BurnerLoansModularTest {
    uint128 internal constant _COLLATERAL_AMOUNT = 2_000e6;
    uint128 internal constant _BORROW_AMOUNT = 100e9;
    uint256 internal constant _DISTRIBUTOR_RECEIPT = 7;

    // Scenarios: TASK-P06.
    function test_givenBurnerLoansPendingFee_taskSettlesOnlyDistributorCustody(
        bool coreActive_,
        bool payoutActive_
    ) public {
        RevenueDistributor distributor = new RevenueDistributor(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        distributor.enable("");
        distributor.setAssetRoutes(address(_asset), 0, new IRevenueDistributor.AssetRoute[](0));
        _payout.setRevenueDistributor(address(distributor));
        _payout.setSendFeesToDistributor(true);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), _COLLATERAL_AMOUNT, _borrower);
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSelector(_asset.transfer.selector, address(distributor)),
            abi.encodeWithSignature("TransferBlocked()")
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory borrowed = _debt.borrow(
            address(_asset),
            _BORROW_AMOUNT,
            _borrower,
            _borrower,
            type(uint256).max
        );
        assertGt(borrowed.fee, 0, "Real borrow creates a fee");
        assertEq(borrowed.resultingDebtOhm, _BORROW_AMOUNT, "Real borrow records principal");
        assertEq(_ohm.balanceOf(_borrower), _BORROW_AMOUNT, "Borrower receives OHM");
        assertEq(
            _asset.balanceOf(address(_payout)),
            borrowed.fee,
            "Deferred fee remains in Payout custody"
        );
        vm.clearMockedCalls();

        address heart = makeAddr("revenue distributor heart");
        RevenueDistributorTask task = new RevenueDistributorTask(
            _kernel,
            address(distributor),
            5_000_000
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(task));
        _rolesAdmin.grantRole(HEART_ROLE, heart);
        task.enable("");
        if (!coreActive_) _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        if (!payoutActive_) _kernel.executeAction(Actions.DeactivatePolicy, address(_payout));
        _asset.mint(address(distributor), _DISTRIBUTOR_RECEIPT);
        address treasury = address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
        uint256 treasuryBefore = _asset.balanceOf(treasury);

        vm.prank(heart);
        task.execute();

        assertEq(
            _asset.balanceOf(treasury) - treasuryBefore,
            _DISTRIBUTOR_RECEIPT,
            "Task settles distributor custody only"
        );
        assertEq(
            _payout.pendingPayout(address(_asset), address(distributor)),
            borrowed.fee,
            "Task leaves deferred Burner Loans fee owed"
        );
        (uint256 pendingFee, uint256 seized, uint256 total) = _payout.payoutReserves(
            address(_asset)
        );
        assertEq(pendingFee, borrowed.fee, "Raw fee bucket is unchanged");
        assertEq(seized, 0, "No seizure liability created");
        assertEq(total, borrowed.fee, "Aggregate Payout reserve is unchanged");
        assertEq(_asset.balanceOf(address(_payout)), borrowed.fee, "Payout custody is untouched");

        // Distributor settlement is independent of Payout membership; a direct retry is not.
        if (!payoutActive_) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                    address(_payout)
                )
            );
            _payout.transferPendingPayout(address(_asset), address(distributor));
            assertEq(
                _payout.pendingPayout(address(_asset), address(distributor)),
                borrowed.fee,
                "Inactive retry preserves fee"
            );
            assertEq(
                _asset.balanceOf(address(_payout)),
                borrowed.fee,
                "Inactive retry preserves custody"
            );
            _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        }
        // Active Payout recovery remains independent of Core membership.
        assertEq(
            _payout.transferPendingPayout(address(_asset), address(distributor)),
            borrowed.fee,
            "Direct retry transfers fee once"
        );
        vm.prank(heart);
        task.execute();
        assertEq(
            _asset.balanceOf(treasury) - treasuryBefore,
            _DISTRIBUTOR_RECEIPT + borrowed.fee,
            "Task settles fee only after direct delivery"
        );
        assertEq(
            _payout.pendingPayout(address(_asset), address(distributor)),
            0,
            "Fee entitlement clears once"
        );
        assertEq(_asset.balanceOf(address(_payout)), 0, "Payout custody clears once");
        assertEq(_asset.balanceOf(address(distributor)), 0, "Distributor custody is fully settled");
    }
}
