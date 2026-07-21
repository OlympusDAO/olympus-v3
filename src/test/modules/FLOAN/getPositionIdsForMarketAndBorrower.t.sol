// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetPositionIdsForMarketAndBorrowerTest is FLOANTest {
    // getPositionIdsForMarketAndBorrower
    // given multiple positions
    //  when getPositionIdsForMarketAndBorrower is called
    //   then it intersects indexes
    function test_givenMultiplePositions_getPositionIdsForMarketAndBorrower_intersectsIndexes()
        public
    {
        uint32 firstMarket = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 secondMarket = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 first = _createPosition(firstMarket, facility, borrower);
        uint64 second = _createPosition(firstMarket, facility, borrower);
        _createPosition(firstMarket, facility, otherBorrower);
        _createPosition(secondMarket, facility, borrower);

        uint256[] memory ids = floan.getPositionIdsForMarketAndBorrower(firstMarket, borrower);
        assertEq(ids.length, 2, "position count");
        assertTrue(ids[0] == first || ids[1] == first, "first position missing");
        assertTrue(ids[0] == second || ids[1] == second, "second position missing");
    }

    // getPositionIdsForMarketAndBorrower
    // given missing market
    //  when getPositionIdsForMarketAndBorrower is called
    //   then it reverts
    function test_givenMissingMarket_getPositionIdsForMarketAndBorrower_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, 0));
        floan.getPositionIdsForMarketAndBorrower(0, borrower);
    }
}
