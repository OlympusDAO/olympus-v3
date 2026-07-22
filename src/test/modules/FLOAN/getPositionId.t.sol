// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetPositionIdTest is FLOANTest {
    function test_givenNoPosition_getPositionIdForMarketAndBorrower_returnsZero() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        (uint256 count, uint64 positionId) = floan.getPositionIdForMarketAndBorrower(
            marketId,
            borrower
        );
        assertEq(count, 0, "pair count");
        assertEq(positionId, 0, "empty id");
    }

    function test_givenMultiplePositions_getPositionIdForMarketAndBorrower_returnsCountAndFirstId()
        public
    {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 first = _createPosition(marketId, facility, borrower);
        _createPosition(marketId, facility, borrower);

        (uint256 count, uint64 positionId) = floan.getPositionIdForMarketAndBorrower(
            marketId,
            borrower
        );
        assertEq(count, 2, "pair count");
        assertEq(positionId, first, "first id");
    }

    function test_givenMissingMarket_getPositionIdForMarketAndBorrower_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, 0));
        floan.getPositionIdForMarketAndBorrower(0, borrower);
    }
}
