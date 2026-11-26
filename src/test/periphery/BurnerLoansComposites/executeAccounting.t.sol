// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";

// Contracts
import {BurnerLoansCompositesTest} from "./fixtures/BurnerLoansCompositesTest.sol";

contract BurnerLoansCompositesExecuteAccountingTest is BurnerLoansCompositesTest {
    // Scenarios: BLREX-I03.
    function test_whenFundingTokenIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InvalidToken.selector,
                address(0)
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(0), 0),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
    }

    // Scenarios: BLREX-I03.
    function test_whenFundingTokenHasNoCode_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InvalidToken.selector,
                _recipient
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(_recipient, 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
    }

    // Scenarios: BLREX-I04.
    function test_whenDepositAbiAmountExceedsUint128_reverts() public {
        IExecutor.Operation memory operation = IExecutor.Operation(
            IExecutor.OperationKind.Deposit,
            abi.encode(address(_asset), uint256(type(uint128).max) + 1)
        );
        vm.prank(_borrower);
        (bool success, bytes memory reason) = address(_executor).call(
            abi.encodeCall(
                IExecutor.execute,
                (
                    _funding(address(_asset), 1),
                    _single(operation),
                    new IExecutor.Output[](0),
                    IExecutor.FlashLoan(0, 0),
                    type(uint48).max
                )
            )
        );
        assertFalse(success, "ABI decoder rejects noncanonical narrow amount");
        assertEq(reason.length, 0, "Solidity ABI decoder returns empty error bytes");
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Malformed amount cannot collect funds");
    }

    // Scenarios: BLREX-T04.
    function test_givenReusableGrant_whenInputAllowanceInsufficient_reverts()
        public
        givenReusableGrant
    {
        vm.prank(_borrower);
        _asset.approve(address(_executor), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(_executor),
                1,
                2
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_asset), 2),
            _single(_deposit(2)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_position().depositedCollateral, 0, "Failed input creates no collateral");
    }

    // Scenarios: BLREX-T06.
    function test_givenReusableGrant_whenFeeExceedsAvailableFunds_reverts()
        public
        givenReusableGrant
    {
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(2000e6);
        operations[1] = _borrow(100e9, type(uint256).max, _borrower);
        _asset.mint(address(_executor), 100e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_FeeExceedsMax.selector,
                312_500,
                312_499
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_asset), 2000e6 + 312_499),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(
            _asset.balanceOf(address(_executor)),
            100e6,
            "Protected funds cannot cover fee shortfall"
        );
        assertEq(_position().depositedCollateral, 0, "Earlier deposit restored");
    }

    // Scenarios: BLREX-T06, BLREX-N05.
    function test_givenReusableGrant_whenFeeExceedsCallerMaximum_reverts()
        public
        givenReusableGrant
    {
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](2);
        operations[0] = _deposit(2000e6);
        operations[1] = _borrow(100e9, 312_499, _borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_FeeExceedsMax.selector,
                312_500,
                312_499
            )
        );
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_asset), 2100e6),
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_core.totalActiveDebtOhm(), 0, "Fee ceiling rejection creates no principal");
    }
}
