// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANCreatePositionTest is FLOANTest {
    function test_createPosition_allowsMultiplePositionsAndIndexesEach() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 firstPositionId = floan.createPosition(marketId, borrower);
        uint64 secondPositionId = floan.createPosition(marketId, borrower);
        vm.stopPrank();

        uint256[] memory borrowerIds = floan.getPositionIdsForBorrower(borrower);
        uint256[] memory marketIds = floan.getPositionIdsForMarket(marketId);
        uint256[] memory pairIds = floan.getPositionIdsForMarketAndBorrower(marketId, borrower);
        assertEq(firstPositionId, 0, "first position id");
        assertEq(secondPositionId, 1, "second position id");
        assertEq(borrowerIds.length, 2, "borrower index length");
        assertEq(marketIds.length, 2, "market index length");
        assertEq(pairIds.length, 2, "pair index length");
        assertEq(pairIds[0], firstPositionId, "first pair position");
        assertEq(pairIds[1], secondPositionId, "second pair position");
    }
}
