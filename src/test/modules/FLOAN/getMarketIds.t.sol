// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetMarketIdsTest is FLOANTest {
    function test_getMarketIds_givenMissingMarket_returnsEmptyArray() public view {
        uint256[] memory marketIds = floan.getMarketIds(facility, collateralToken, debtToken);

        assertEq(marketIds.length, 0, "market count");
    }

    function test_getMarketIds_givenMarketZero_returnsMarketZero() public {
        _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        uint256[] memory marketIds = floan.getMarketIds(facility, collateralToken, debtToken);

        assertEq(marketIds.length, 1, "market count");
        assertEq(marketIds[0], 0, "market id");
    }

    function test_getMarketIds_givenMultipleMarketsForPair_returnsEveryMarket() public {
        uint32 first = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 second = _createMarket(manager, facility, collateralToken, debtToken, 2_000e9);

        uint256[] memory marketIds = floan.getMarketIds(facility, collateralToken, debtToken);

        assertEq(marketIds.length, 2, "market count");
        assertEq(marketIds[0], first, "first market id");
        assertEq(marketIds[1], second, "second market id");
    }

    function test_getMarketIds_givenDifferentTuples_keepsIndexesSeparate() public {
        uint32 matching = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createMarket(manager, otherFacility, collateralToken, debtToken, 1_000e9);
        _createMarket(manager, facility, otherCollateralToken, debtToken, 1_000e9);
        _createMarket(manager, facility, collateralToken, otherDebtToken, 1_000e9);

        uint256[] memory marketIds = floan.getMarketIds(facility, collateralToken, debtToken);

        assertEq(marketIds.length, 1, "market count");
        assertEq(marketIds[0], matching, "matching market id");
    }
}
