// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansPreviewDepositCollateralTest is BurnerLoansTest {
    function setUp() public override {
        super.setUp();
        _addDefaultUsdsAsset();
    }

    // previewDepositCollateral
    // given existing collateral
    //  when previewDepositCollateral is called
    //   then it returns increment and total
    function test_givenExistingCollateral_previewDepositCollateral_returnsIncrementAndTotal()
        public
    {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 400e6,
                debtOhm: 0,
                maturity: 0,
                lastBorrowBlock: 0,
                status: IBurnerLoans.PositionStatus.NoDebt
            })
        );

        (uint256 deposited, uint256 total) = burnerLoans.previewDepositCollateral(
            address(usds),
            100e6,
            alice
        );
        assertEq(deposited, 100e6, "deposited");
        assertEq(total, 500e6, "total");
    }
}
