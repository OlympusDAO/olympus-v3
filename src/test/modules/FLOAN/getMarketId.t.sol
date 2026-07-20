// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetMarketIdTest is FLOANTest {
    function test_getMarketId_givenMissingMarket_returnsFalse() public view {
        (bool exists, uint32 marketId) = floan.getMarketId(facility, collateralToken, debtToken);

        assertFalse(exists, "market should not exist");
        assertEq(marketId, 0, "missing market id");
    }

    function test_getMarketId_givenMarketZero_returnsTrue() public {
        _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        (bool exists, uint32 marketId) = floan.getMarketId(facility, collateralToken, debtToken);

        assertTrue(exists, "market should exist");
        assertEq(marketId, 0, "market zero id");
    }
}
