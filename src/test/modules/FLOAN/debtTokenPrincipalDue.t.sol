// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANDebtTokenPrincipalDueTest is FLOANTest {
    // debtTokenPrincipalDue
    // given several facilities
    //  when debtTokenPrincipalDue is called
    //   then it aggregates by debt token
    function test_givenSeveralFacilities_debtTokenPrincipalDue_aggregatesByDebtToken() public {
        uint32 first = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 second = _createMarket(manager, otherFacility, collateralToken, debtToken, 1_000e9);
        _createPositionWithDebt(first, facility, borrower, 100e9);
        _createPositionWithDebt(second, otherFacility, borrower, 200e9);

        assertEq(floan.debtTokenPrincipalDue(debtToken), 300e9, "debt token principal");
        assertEq(floan.debtTokenPrincipalDue(otherDebtToken), 0, "other debt token principal");
    }
}
