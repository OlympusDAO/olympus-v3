// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetActiveBorrowersTest is FLOANTest {
    // getActiveBorrowers
    // given several positions
    //  when getActiveBorrowers is called
    //   then it returns unique debt borrowers
    function test_givenSeveralPositions_getActiveBorrowers_returnsUniqueDebtBorrowers() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.startPrank(facility);
        uint64 first = floan.createPosition(marketId, borrower);
        uint64 second = floan.createPosition(marketId, borrower);
        uint64 third = floan.createPosition(marketId, otherBorrower);
        uint48 maturity = uint48(block.timestamp + 30 days);
        floan.increaseDebt(first, 100e9, 0, maturity);
        floan.increaseDebt(second, 100e9, 0, maturity);
        floan.increaseDebt(third, 100e9, 0, maturity);
        vm.stopPrank();

        address[] memory borrowers = floan.getActiveBorrowers(marketId);
        assertEq(borrowers.length, 2, "active borrower count");
        assertTrue(borrowers[0] == borrower || borrowers[1] == borrower, "first borrower missing");
        assertTrue(
            borrowers[0] == otherBorrower || borrowers[1] == otherBorrower,
            "second borrower missing"
        );
    }

    // getActiveBorrowers
    // given missing market
    //  when getActiveBorrowers is called
    //   then it reverts
    function test_givenMissingMarket_getActiveBorrowers_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, 0));
        floan.getActiveBorrowers(0);
    }
}
