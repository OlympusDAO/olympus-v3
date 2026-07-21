// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansPreviewWithdrawCollateralTest is BurnerLoansTest {
    function setUp() public override {
        super.setUp();
        _addDefaultUsdsAsset();
    }

    // previewWithdrawCollateral
    // given debt free position
    //  when previewWithdrawCollateral is called
    //   then it returns executable quote
    function test_givenDebtFreePosition_previewWithdrawCollateral_returnsExecutableQuote() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 500e6,
                debtOhm: 0,
                maturity: 0,
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.NoDebt
            })
        );

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            100e6,
            alice
        );
        assertEq(preview.returnToken, address(usds), "return token");
        assertEq(preview.returnAmount, 100e6, "return amount");
        assertEq(preview.remainingDepositedCollateral, 400e6, "remaining collateral");
        assertEq(preview.resultingHealthFactor, type(uint256).max, "health");
        assertTrue(preview.executable, "executable");
    }
}
