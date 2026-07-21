// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";

contract BurnerLoansPreviewBorrowTest is BurnerLoansBorrowTestBase {
    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    // previewBorrow
    // given healthy first borrow
    //  when previewBorrow is called
    //   then it returns executable quote
    function test_givenHealthyFirstBorrow_previewBorrow_returnsExecutableQuote() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 2_000e18,
                debtOhm: 0,
                maturity: 0,
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.NoDebt
            })
        );

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            100e9,
            alice
        );
        assertEq(preview.resultingDebtOhm, 100e9, "resulting debt");
        assertEq(preview.maturity, block.timestamp + 30 days, "maturity");
        assertGt(preview.fee, 0, "fee");
        assertGt(preview.resultingHealthFactor, 1e18, "health");
        assertTrue(preview.executable, "executable");
    }
}
