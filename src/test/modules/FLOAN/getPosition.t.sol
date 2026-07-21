// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetPositionTest is FLOANTest {
    // getPosition
    // given existing position
    //  when getPosition is called
    //   then it returns stored position
    function test_givenExistingPosition_getPosition_returnsStoredPosition() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        IFLOANv1.Position memory position = floan.getPosition(positionId);
        assertEq(position.borrower, borrower, "borrower");
        assertEq(position.marketId, marketId, "market id");
        assertEq(position.principalDrawn, 100e9, "principal drawn");
        assertEq(position.principalDue, 100e9, "principal due");
    }

    // getPosition
    // given missing position
    //  when getPosition is called
    //   then it reverts
    function test_givenMissingPosition_getPosition_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidPosition.selector, 0));
        floan.getPosition(0);
    }
}
