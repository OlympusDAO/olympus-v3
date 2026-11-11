// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansDebtPriceCallbackTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtPriceCallbackTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast, unused-return)

contract BurnerLoansDebtRepayPriceCallbacksTest is BurnerLoansDebtPriceCallbackTest {
    // Scenarios: BLDEBT-REPAY-C01.
    function test_givenCacheBorrows_whenPartialRepayRefreshes_thenLatestBorrowBlockRechecked()
        public
    {
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0, address(0));
        vm.roll(vm.getBlockNumber() + 1);
        vm.prank(_borrower);
        _ohm.approve(address(_core), type(uint256).max);
        _cache.arm(
            address(_debt),
            abi.encodeCall(
                _debt.borrow,
                (address(_asset), 1, _borrower, address(_cache), uint256(0), address(0))
            ),
            true
        );
        bytes32 rollbackBefore = _priceStateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_SameBlockRepay.selector,
                uint48(block.number)
            )
        );
        vm.prank(_borrower);
        _debt.repay(address(_asset), 1, _borrower);
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Nested borrow and outer repay roll back");
        assertEq(
            _priceStateDigest(),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-REPAY-C05.
    function test_givenCacheFullyRepays_whenOuterReloads_thenExcessRepaymentRejected() public {
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 100e9, _borrower, _borrower, 0, address(0));
        vm.roll(block.number + 1);
        _ohm.mint(address(_cache), 100e9);
        vm.prank(address(_cache));
        _ohm.approve(address(_core), 100e9);
        _cache.arm(
            address(_debt),
            abi.encodeCall(_debt.repay, (address(_asset), 100e9, _borrower)),
            true
        );
        bytes32 rollbackBefore = _priceStateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_RepayExceedsDebt.selector,
                uint256(1),
                uint256(0)
            )
        );
        vm.prank(_borrower);
        _debt.repay(address(_asset), 1, _borrower);
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Nested full repayment rolled back");
        assertEq(_ohm.balanceOf(address(_cache)), 100e9, "Nested payer funds restored");
        assertEq(
            _priceStateDigest(),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-REPAY-C06.
    function test_givenCachePartiallyRepays_whenOuterAmountTooLarge_thenLiveDebtRechecked() public {
        _prepareDebtAndCacheRepayer();
        _cache.arm(
            address(_debt),
            abi.encodeCall(_debt.repay, (address(_asset), 75e9, _borrower)),
            true
        );
        bytes32 rollbackBefore = _priceStateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_RepayExceedsDebt.selector,
                uint256(50e9),
                uint256(25e9)
            )
        );
        vm.prank(_borrower);
        _debt.repay(address(_asset), 50e9, _borrower);
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Nested partial repayment rolls back");
        assertEq(_ohm.balanceOf(address(_cache)), 100e9, "Nested payer restored");
        assertEq(
            _priceStateDigest(),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-REPAY-C03.
    function test_givenCaughtUnauthorizedCacheBorrow_whenRepaying_thenOneRepayment() public {
        _prepareDebtAndCacheRepayer();
        _armUnauthorizedBorrow(false);
        vm.prank(_borrower);
        _debt.repay(address(_asset), 1, _borrower);
        assertEq(_inventory.activePrincipalOhm(), 100e9 - 1, "Only outer repayment");
        assertEq(
            _cache.rejection(),
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidContext.selector),
            "Exact caught failure"
        );
    }

    // Scenarios: BLDEBT-REPAY-C04.
    function test_givenPropagatedUnauthorizedCacheBorrow_whenRepaying_thenRollback() public {
        _prepareDebtAndCacheRepayer();
        _armUnauthorizedBorrow(true);
        bytes32 rollbackBefore = _priceStateDigest();
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(_borrower);
        _debt.repay(address(_asset), 1, _borrower);
        assertEq(_inventory.activePrincipalOhm(), 100e9, "No repayment after refresh failure");
        assertEq(
            _priceStateDigest(),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unsafe-typecast, unused-return)
