// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANFacilityPrincipalDueTest is FLOANTest {
    function test_givenSeveralMarkets_facilityPrincipalDue_aggregatesByFacilityAndDebtToken()
        public
    {
        uint32 first = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 second = _createMarket(manager, facility, otherCollateralToken, debtToken, 1_000e9);
        uint32 otherDebt = _createMarket(
            manager,
            facility,
            collateralToken,
            otherDebtToken,
            1_000e9
        );
        _createPositionWithDebt(first, facility, borrower, 100e9);
        _createPositionWithDebt(second, facility, borrower, 200e9);
        _createPositionWithDebt(otherDebt, facility, borrower, 400e9);

        assertEq(floan.facilityPrincipalDue(facility, debtToken), 300e9, "facility principal");
        assertEq(
            floan.facilityPrincipalDue(facility, otherDebtToken),
            400e9,
            "other debt principal"
        );
        assertEq(floan.facilityPrincipalDue(otherFacility, debtToken), 0, "other facility");
    }
}
