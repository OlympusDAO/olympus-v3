// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {BurnerLoansCompositesTest} from "./fixtures/BurnerLoansCompositesTest.sol";

contract BurnerLoansCompositesExecuteServicingTest is BurnerLoansCompositesTest {
    error UnexpectedDependencyRead();

    function _withdraw(
        uint128 amount_,
        address tokenOut_,
        uint256 minimum_
    ) internal view returns (IExecutor.Operation memory) {
        return
            IExecutor.Operation(
                IExecutor.OperationKind.Withdraw,
                abi.encode(
                    IExecutor.Withdraw(
                        address(_asset),
                        amount_,
                        address(_executor),
                        tokenOut_,
                        minimum_
                    )
                )
            );
    }

    function _openOlderDebt() private {
        vm.startPrank(_borrower);
        _collateral.depositCollateral(address(_asset), 2000e6, _borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 100e6, address(0));
        _ohm.approve(address(_executor), type(uint256).max);
        vm.stopPrank();
        vm.roll(block.number + 1);
    }

    modifier givenOlderDebt() {
        _openOlderDebt();
        _;
    }

    // Scenarios: BLREX-A10, BLREX-O12.
    function test_givenOlderDebt_whenRepayWithoutAuthOrPrices() public givenOlderDebt {
        _ohm.mint(_borrower, 10e9);
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(address(_ohm), 10e9);
        uint256 inventoryBefore = _ohm.balanceOf(address(_inventory));
        uint256 supplyBefore = _ohm.totalSupply();
        _blockRepaymentDependencyReads();
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_ohm), 110e9),
            _single(_repay(100e9)),
            outputs,
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(
            abi.decode(results[0], (uint128)),
            0,
            "Repayment returns only remaining principal"
        );
        assertEq(_position().debtOhm, 0, "Canonical principal repaid");
        assertEq(_core.totalActiveDebtOhm(), 0, "Core principal reconciled");
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory principal reconciled");
        // This fixture borrows minted OHM, so Inventory burns the exact repayment after receiving it.
        assertEq(
            _ohm.balanceOf(address(_inventory)),
            inventoryBefore,
            "Minted repayment leaves no Inventory surplus"
        );
        assertEq(_ohm.totalSupply(), supplyBefore - 100e9, "Actual repaid minted principal burned");
        assertEq(
            _ohm.balanceOf(_borrower),
            10e9,
            "Unused repayment funding satisfies return minimum"
        );
        assertEq(_ohm.allowance(address(_executor), address(_core)), 0, "Repay allowance cleared");
    }

    // Scenarios: BLREX-A10.
    function test_givenInventorySupply_whenRepayWithoutAuthOrPrices() public {
        _supplyInventory(_recipient, 150e9);
        _openOlderDebt();
        assertEq(_inventory.suppliedIdleOhm(), 50e9, "Borrow uses 100 out of 150 supplied OHM");
        uint256 supply = _ohm.totalSupply();
        _blockRepaymentDependencyReads();
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_ohm), 100e9),
            _single(_repay(100e9)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_position().debtOhm, 0, "Provider-funded position repaid grantlessly");
        assertEq(_core.totalActiveDebtOhm(), 0, "Core principal reconciled");
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory principal reconciled");
        assertEq(_inventory.suppliedIdleOhm(), 150e9, "Repayment restores supplied liquidity");
        assertEq(_ohm.balanceOf(address(_inventory)), 150e9, "Inventory holds restored supply");
        assertEq(_ohm.totalSupply(), supply, "Provider principal is retained");
        assertEq(_ohm.balanceOf(_borrower), 0, "Repayment consumes exact wallet OHM");
    }

    function _blockRepaymentDependencyReads() private {
        bytes memory reason = abi.encodeWithSelector(UnexpectedDependencyRead.selector);
        vm.mockCallRevert(address(_core), abi.encodeCall(IBurnerLoansCore.authConfig, ()), reason);
        vm.mockCallRevert(address(_auth), bytes(""), reason);
        vm.mockCallRevert(address(_risk), bytes(""), reason);
        vm.mockCallRevert(address(_price), bytes(""), reason);
    }

    // Scenarios: BLREX-P02, BLREX-P04.
    function test_givenOlderDebt_givenReusableGrant_whenRepayAndWithdraw()
        public
        givenOlderDebt
        givenReusableGrant
    {
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        _asset.mint(address(_executor), 7e6);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _repay(100e9);
        operations[1] = _withdraw(2000e6, address(_asset), 2000e6);
        vm.prank(_borrower);
        bytes[] memory results = _executor.execute(
            _funding(address(_ohm), 100e9),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        IBurnerLoansCollateral.WithdrawPreview memory withdrawn = abi.decode(
            results[1],
            (IBurnerLoansCollateral.WithdrawPreview)
        );
        assertEq(withdrawn.returnToken, address(_asset), "Underlying token reported");
        assertEq(withdrawn.returnAmount, 2000e6, "Raw withdrawal amount reported");
        assertEq(_position().debtOhm, 0, "Principal closed");
        assertEq(_position().depositedCollateral, 0, "Collateral fully withdrawn");
        assertEq(_asset.balanceOf(address(_depositManager)), 0, "Custody fully settled");
        assertEq(_asset.balanceOf(address(_executor)), 7e6, "Protected underlying retained");
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet + 2000e6,
            "Withdrawn funds refunded to EOA"
        );
    }
}
