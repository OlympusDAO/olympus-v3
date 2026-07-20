// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetOrCreatePositionTest is FLOANTest {
    function test_getOrCreatePosition_returnsCanonicalPositionForPair() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 firstPositionId = floan.getOrCreatePosition(marketId, borrower);
        uint64 secondPositionId = floan.getOrCreatePosition(marketId, borrower);
        vm.stopPrank();

        (bool exists, uint64 lookupId) = floan.getPositionId(marketId, borrower);
        assertTrue(exists, "default position exists");
        assertEq(firstPositionId, secondPositionId, "same position returned");
        assertEq(lookupId, firstPositionId, "lookup position id");
        assertEq(floan.positionCount(), 1, "one position created");
    }
}
