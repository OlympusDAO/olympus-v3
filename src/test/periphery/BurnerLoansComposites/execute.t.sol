// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";

// Contracts
import {BurnerLoansCompositesTest} from "./fixtures/BurnerLoansCompositesTest.sol";

contract BurnerLoansCompositesExecuteTest is BurnerLoansCompositesTest {
    // Scenarios: BLREX-I01.
    function test_whenOperationsAreEmpty_reverts() public {
        vm.expectRevert(IExecutor.BurnerLoansComposites_EmptyOperations.selector);
        _executor.execute(
            new IExecutor.Funding[](0),
            new IExecutor.Operation[](0),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
    }

    // Scenarios: BLREX-P01, BLREX-O04.
    function test_givenReusableGrant_whenDepositAndBorrow() public givenReusableGrant {
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(2000e6);
        operations[1] = _borrow(100e9, 100e6, _borrower);
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(address(_ohm), 100e9);
        vm.expectEmit(address(_executor));
        emit IExecutor.OperationsExecuted(_borrower, 2);
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_asset), 2100e6),
            operations,
            outputs,
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        IBurnerLoansDebt.BorrowPreview memory borrowed = abi.decode(
            results[1],
            (IBurnerLoansDebt.BorrowPreview)
        );
        assertEq(
            results[0],
            abi.encode(uint128(2000e6), uint128(2000e6)),
            "Deposit returns credit and total collateral"
        );
        // 100 OHM (9 decimals) at $1: max(100 / 0.85, 100 * 1.25) = $125 required.
        // Zero prior market utilization gives 25 bps. Six-decimal fee = 125e6 * 25 / 10_000.
        assertEq(borrowed.fee, 312_500, "Independently derived origination fee");
        assertEq(_position().depositedCollateral, 2000e6, "Canonical position collateral");
        assertEq(_position().debtOhm, 100e9, "Canonical position principal");
        assertEq(_core.totalActiveDebtOhm(), 100e9, "Core aggregate principal");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Inventory aggregate principal");
        assertEq(_ohm.balanceOf(_borrower), 100e9, "EOA receives principal");
        assertEq(_asset.balanceOf(_borrower), 8000e6 - 312_500, "Unused fee budget refunded");
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            2000e6,
            "Actual custody receives deposit"
        );
        assertEq(_asset.balanceOf(address(_executor)), 0, "No execution collateral retained");
        assertEq(_asset.allowance(address(_executor), address(_core)), 0, "Core approval cleared");
    }

    // Scenarios: BLREX-T01.
    function test_givenProtectedBalance_whenInputBudgetIsTooSmall_reverts()
        public
        givenReusableGrant
    {
        _asset.mint(address(_executor), 100e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                address(_asset),
                101e6,
                1e6
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_asset), 1e6),
            _single(_deposit(101e6)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_asset.balanceOf(address(_executor)), 100e6, "Protected balance retained");
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Wallet pull reverted");
        assertEq(_position().depositedCollateral, 0, "No collateral credited");
    }

    // Scenarios: BLREX-I02.
    function test_whenDuplicateFunding_reverts() public {
        IExecutor.Funding[] memory inputs = new IExecutor.Funding[](2);
        inputs[0] = IExecutor.Funding(address(_asset), 1e6);
        inputs[1] = IExecutor.Funding(address(_asset), 1e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_DuplicateFunding.selector,
                address(_asset)
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            inputs,
            _single(_deposit(1e6)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Duplicate funding collects nothing");
    }

    // Scenarios: BLREX-T02.
    function test_givenProtectedBalance_whenDepositAndRefund() public givenReusableGrant {
        _asset.mint(address(_executor), 50e6);
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_asset), 15e6),
            _single(_deposit(10e6)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_asset.balanceOf(address(_executor)), 50e6, "Only execution surplus is refunded");
        assertEq(_asset.balanceOf(_borrower), 9990e6, "Caller pays only deposited amount");
        assertEq(
            _asset.allowance(address(_executor), address(_core)),
            0,
            "Deposit allowance cleared"
        );
    }
}
