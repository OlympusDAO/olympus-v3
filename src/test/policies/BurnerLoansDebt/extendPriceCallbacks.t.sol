// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansDebtPriceCallbackTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtPriceCallbackTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

contract BurnerLoansDebtExtendPriceCallbacksTest is BurnerLoansDebtPriceCallbackTest {
    // Scenarios: BLEXT-EXTEND-C01.
    function test_givenCacheFullyRepays_whenExtensionReloads_thenNoDebtAndRollback() public {
        _prepareDebtAndCacheRepayer();
        _cache.arm(
            address(_debt),
            abi.encodeCall(_debt.repay, (address(_asset), 100e9, _borrower)),
            true
        );
        bytes32 rollbackBefore = _priceStateDigest();
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_NoDebt.selector);
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, 0);
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Nested full repayment rolls back");
        assertEq(_ohm.balanceOf(address(_cache)), 100e9, "Nested payer restored");
        assertEq(
            _priceStateDigest(),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLEXT-EXTEND-C03.
    function test_givenCaughtUnauthorizedCacheBorrow_whenExtending_thenOneExtension() public {
        _prepareDebtAndCacheRepayer();
        _armUnauthorizedBorrow(false);
        vm.prank(_borrower);
        IBurnerLoansDebt.ExtendPreview memory result = _debt.extend(
            address(_asset),
            _borrower,
            1,
            0
        );
        assertEq(result.maturity, block.timestamp + 60 days, "Only outer extension");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Debt unchanged");
    }

    // Scenarios: BLEXT-EXTEND-C04.
    function test_givenPropagatedUnauthorizedCacheBorrow_whenExtending_thenRollback() public {
        _prepareDebtAndCacheRepayer();
        _armUnauthorizedBorrow(true);
        bytes32 rollbackBefore = _priceStateDigest();
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        vm.prank(_borrower);
        _debt.extend(address(_asset), _borrower, 1, 0);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).maturity,
            block.timestamp + 30 days,
            "No extension after refresh failure"
        );
        assertEq(
            _priceStateDigest(),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
