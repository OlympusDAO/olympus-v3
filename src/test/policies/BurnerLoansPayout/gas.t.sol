// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {Actions, toKeycode} from "src/Kernel.sol";
import {RevenueDistributor} from "src/policies/RevenueDistributor.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

// Each contract retains its original snapshot group. Setup uses real modular settlement.
// forge-lint: disable-start(multi-contract-file, unused-return)
abstract contract BurnerLoansPayoutGasTest is BurnerLoansModularTest {
    function _distributor() internal returns (RevenueDistributor distributor) {
        distributor = new RevenueDistributor(_kernel);
        _kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        distributor.enable("");
        _payout.setRevenueDistributor(address(distributor));
    }

    function _openLoan() internal {
        vm.startPrank(_borrower);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, type(uint256).max);
        vm.stopPrank();
    }

    function _treasury() internal view returns (address) {
        return address(_kernel.getModuleForKeycode(toKeycode("TRSRY")));
    }
}

contract BurnerLoansTransferPendingPayoutTest is BurnerLoansPayoutGasTest {
    function test_givenPendingFee_whenDistributorChanges_thenRetryPaysNewDistributor() public {
        RevenueDistributor former = _distributor();
        _payout.setSendFeesToDistributor(true);
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSelector(_asset.transfer.selector, address(former)),
            abi.encodeWithSignature("BlockedTransfer()")
        );
        _openLoan();
        (uint256 fee, , ) = _payout.payoutReserves(address(_asset));
        assertGt(fee, 0, "Real borrow creates a pending fee");
        vm.clearMockedCalls();
        RevenueDistributor current = _distributor();
        address[] memory recipients = _payout.getPendingPayoutRecipients(address(_asset));
        assertEq(recipients.length, 1, "Exactly one pending fee recipient");
        assertEq(recipients[0], address(current), "Recipient list follows replacement");
        _payout.transferPendingPayout(address(_asset), address(former));
        assertEq(
            _payout.pendingPayout(address(_asset), address(current)),
            fee,
            "Fee follows replacement before retry"
        );
        vm.startSnapshotGas("BurnerLoansPayout.transferPendingPayout.feeToReplacementDistributor");
        uint256 paid = _payout.transferPendingPayout(address(_asset), address(current));
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Replacement retry gas recorded");
        assertEq(paid, fee, "Retry returns the exact pending fee");
        assertEq(_asset.balanceOf(address(former)), 0, "Former distributor receives nothing");
        assertEq(_asset.balanceOf(address(current)), fee, "Replacement receives old fee");
        assertEq(_payout.pendingPayout(address(_asset), address(current)), 0, "Fee clears once");
    }
}

contract BurnerLoansTransferPendingSeizurePayoutTest is BurnerLoansPayoutGasTest {
    function test_givenFeeAndSeizurePending_transfersBothAmounts() public {
        address treasury = _treasury();
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSelector(_asset.transfer.selector, treasury),
            abi.encodeWithSignature("BlockedTransfer()")
        );
        _openLoan();
        uint256 fee = _payout.pendingPayout(address(_asset), treasury);
        IBurnerLoansCore.Position memory position = _lens.getPosition(address(_asset), _borrower);
        vm.warp(position.maturity);
        _price.setTimestamp(position.maturity);
        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        IBurnerLoansCore.SeizePreview memory preview = _liquidation.previewSeizeFor(
            address(this),
            address(_asset),
            borrowers
        );
        (, uint256 reward, uint256 seized) = _liquidation.seize(address(_asset), borrowers);
        assertEq(reward, preview.keeperReward, "Seizure returns quoted keeper reward");
        assertEq(seized, preview.collateralToTreasury, "Seizure returns quoted Treasury amount");
        assertEq(seized + reward, 2000e6, "Entire collateral allocated on default");
        vm.clearMockedCalls();
        address[] memory recipients = _payout.getPendingPayoutRecipients(address(_asset));
        assertEq(recipients.length, 1, "Fee and seizure share one pending recipient");
        assertEq(recipients[0], treasury, "Treasury listed once");
        uint256 beforeBalance = _asset.balanceOf(treasury);
        vm.startSnapshotGas("BurnerLoansPayout.transferPendingPayout.feeAndSeizure");
        uint256 paid = _payout.transferPendingPayout(address(_asset), treasury);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Combined retry gas recorded");
        assertGt(fee, 0, "Fee was owed before retry");
        assertEq(paid, fee + seized, "Both pending obligations paid");
        assertEq(_asset.balanceOf(treasury) - beforeBalance, paid, "Treasury receives exact retry");
        assertEq(_payout.pendingPayout(address(_asset), treasury), 0, "Treasury buckets clear");
        assertEq(_lens.getPosition(address(_asset), _borrower).debtOhm, 0, "Default clears debt");
    }
}
// forge-lint: disable-end(multi-contract-file, unused-return)
