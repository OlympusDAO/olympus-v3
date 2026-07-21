// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansGetActiveBorrowersTest is BurnerLoansTest {
    // getActiveBorrowers
    // given multiple active positions
    //  when getActiveBorrowers is called
    //   then it returns market borrowers
    function test_givenMultipleActivePositions_getActiveBorrowers_returnsMarketBorrowers() public {
        _addDefaultUsdsAsset();
        address bob = makeAddr("bob");
        IBurnerLoans.Position memory position = IBurnerLoans.Position({
            depositedCollateral: 1_500e6,
            debtOhm: 100e9,
            maturity: uint48(block.timestamp + 30 days),
            lastBorrowBlock: 0,
            status: IBurnerLoans.PositionStatus.NoDebt
        });
        burnerLoans.setPositionForTest(address(usds), alice, position);
        burnerLoans.setPositionForTest(address(usds), bob, position);

        address[] memory borrowers = burnerLoans.getActiveBorrowers(address(usds));
        assertEq(borrowers.length, 2, "borrower count");
        assertEq(borrowers[0], alice, "first borrower");
        assertEq(borrowers[1], bob, "second borrower");
    }
}
