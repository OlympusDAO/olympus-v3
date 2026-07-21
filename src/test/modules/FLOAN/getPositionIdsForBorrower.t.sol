// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetPositionIdsForBorrowerTest is FLOANTest {
    // getPositionIdsForBorrower
    // given positions across markets
    //  when getPositionIdsForBorrower is called
    //   then it returns only borrower positions
    function test_givenPositionsAcrossMarkets_getPositionIdsForBorrower_returnsOnlyBorrowerPositions()
        public
    {
        uint32 firstMarket = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 secondMarket = _createMarket(
            manager,
            facility,
            otherCollateralToken,
            debtToken,
            1_000e9
        );
        uint64 first = _createPosition(firstMarket, facility, borrower);
        uint64 second = _createPosition(secondMarket, facility, borrower);
        _createPosition(firstMarket, facility, otherBorrower);

        uint256[] memory ids = floan.getPositionIdsForBorrower(borrower);
        assertEq(ids.length, 2, "position count");
        assertTrue(ids[0] == first || ids[1] == first, "first position missing");
        assertTrue(ids[0] == second || ids[1] == second, "second position missing");
        assertEq(floan.getPositionIdsForBorrower(otherFacility).length, 0, "empty borrower");
    }
}
