// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANIncreaseDebtTest is FLOANTest {
    function test_updatesMarketFacilityAndTokenPrincipalTotals() public {
        uint32 firstMarket = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 secondMarket = _createMarket(
            manager,
            facility,
            otherCollateralToken,
            debtToken,
            1_000e9
        );
        uint32 otherFacilityMarket = _createMarket(
            manager,
            otherFacility,
            collateralToken,
            debtToken,
            1_000e9
        );

        _createPositionWithDebt(firstMarket, facility, borrower, 100e9);
        _createPositionWithDebt(secondMarket, facility, borrower, 200e9);
        _createPositionWithDebt(otherFacilityMarket, otherFacility, borrower, 400e9);

        assertEq(floan.marketPrincipalDue(firstMarket), 100e9, "first market principal");
        assertEq(floan.marketPrincipalDue(secondMarket), 200e9, "second market principal");
        assertEq(floan.facilityPrincipalDue(facility, debtToken), 300e9, "facility principal");
        assertEq(
            floan.facilityPrincipalDue(otherFacility, debtToken),
            400e9,
            "other facility principal"
        );
        assertEq(floan.debtTokenPrincipalDue(debtToken), 700e9, "token principal");
    }

    function test_interestOnlyIncrease_doesNotChangePrincipalTotals() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 positionId = floan.getOrCreatePosition(marketId, borrower);
        floan.increaseDebt(positionId, 100e9, 25e9, uint48(block.timestamp + 30 days));
        vm.stopPrank();

        assertEq(floan.marketPrincipalDue(marketId), 100e9, "market principal");
        assertEq(floan.facilityPrincipalDue(facility, debtToken), 100e9, "facility principal");
        assertEq(floan.debtTokenPrincipalDue(debtToken), 100e9, "token principal");
    }

    function testFuzz_increaseDebt_updatesEveryPrincipalTotal(uint128 principal_) public {
        principal_ = uint128(bound(principal_, 1, type(uint128).max));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, principal_);

        _createPositionWithDebt(marketId, facility, borrower, principal_);

        assertEq(floan.marketPrincipalDue(marketId), principal_, "market principal");
        assertEq(floan.facilityPrincipalDue(facility, debtToken), principal_, "facility principal");
        assertEq(floan.debtTokenPrincipalDue(debtToken), principal_, "token principal");
    }

    function test_increaseDebt_givenExactPrincipalCap_succeedsAndOneOverReverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 100e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFLOANv1.FLOAN_PrincipalCapExceeded.selector,
                marketId,
                uint128(100e9)
            )
        );
        floan.increaseDebt(positionId, 1, 0, uint48(block.timestamp + 30 days));

        assertEq(floan.marketPrincipalDue(marketId), 100e9, "market principal unchanged");
        assertEq(
            floan.facilityPrincipalDue(facility, debtToken),
            100e9,
            "facility principal unchanged"
        );
    }

    function test_increaseDebt_isolatesDebtTokensWithinFacility() public {
        uint32 firstMarket = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 secondMarket = _createMarket(
            manager,
            facility,
            otherCollateralToken,
            otherDebtToken,
            1_000e9
        );

        _createPositionWithDebt(firstMarket, facility, borrower, 100e9);
        _createPositionWithDebt(secondMarket, facility, borrower, 200e9);

        assertEq(floan.facilityPrincipalDue(facility, debtToken), 100e9, "first token total");
        assertEq(floan.facilityPrincipalDue(facility, otherDebtToken), 200e9, "second token total");
        assertEq(floan.debtTokenPrincipalDue(debtToken), 100e9, "first protocol total");
        assertEq(floan.debtTokenPrincipalDue(otherDebtToken), 200e9, "second protocol total");
    }
}
