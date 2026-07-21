// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANMarketCountTest is FLOANTest {
    // marketCount
    // given no markets
    //  when marketCount is called
    //   then it returns zero
    function test_givenNoMarkets_marketCount_returnsZero() public view {
        assertEq(floan.marketCount(), 0, "market count");
    }

    // marketCount
    // given multiple markets
    //  when marketCount is called
    //   then it returns created count
    function test_givenMultipleMarkets_marketCount_returnsCreatedCount() public {
        _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        assertEq(floan.marketCount(), 2, "market count");
    }
}
