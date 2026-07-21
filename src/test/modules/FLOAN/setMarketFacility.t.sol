// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {Module} from "src/Kernel.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketFacilityTest is FLOANTest {
    // setMarketFacility
    // given caller without kernel permission
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_setMarketFacility_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.setMarketFacility(marketId, otherFacility);
    }

    // setMarketFacility
    // given an existing market with outstanding principal
    //  when setMarketFacility is called
    //   then it moves lookup authority and principal
    function test_setMarketFacility_movesLookupAuthorityAndPrincipal() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(manager);
        floan.setMarketFacility(marketId, otherFacility);

        uint256[] memory oldMarketIds = floan.getMarketIds(facility, collateralToken, debtToken);
        uint256[] memory newMarketIds = floan.getMarketIds(
            otherFacility,
            collateralToken,
            debtToken
        );
        assertEq(oldMarketIds.length, 0, "old lookup should be cleared");
        assertEq(newMarketIds.length, 1, "new lookup market count");
        assertEq(newMarketIds[0], marketId, "new lookup market id");
        assertEq(floan.facilityPrincipalDue(facility, debtToken), 0, "old facility principal");
        assertEq(
            floan.facilityPrincipalDue(otherFacility, debtToken),
            100e9,
            "new facility principal"
        );
        assertEq(floan.marketPrincipalDue(marketId), 100e9, "market principal");
        assertEq(floan.debtTokenPrincipalDue(debtToken), 100e9, "debt token principal");

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, facility)
        );
        floan.addCollateral(positionId, 1);

        vm.prank(otherFacility);
        assertEq(floan.addCollateral(positionId, 1), 1, "new facility collateral mutation");
    }

    // setMarketFacility
    // given duplicate target pair
    //  when setMarketFacility is called
    //   then it indexes both markets
    function test_setMarketFacility_givenDuplicateTargetPair_indexesBothMarkets() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 existingMarketId = _createMarket(
            manager,
            otherFacility,
            collateralToken,
            debtToken,
            1_000e9
        );

        vm.prank(manager);
        floan.setMarketFacility(marketId, otherFacility);

        uint256[] memory oldMarketIds = floan.getMarketIds(facility, collateralToken, debtToken);
        uint256[] memory newMarketIds = floan.getMarketIds(
            otherFacility,
            collateralToken,
            debtToken
        );
        assertEq(oldMarketIds.length, 0, "old lookup should be cleared");
        assertEq(newMarketIds.length, 2, "new lookup market count");
        assertEq(newMarketIds[0], existingMarketId, "existing lookup market id");
        assertEq(newMarketIds[1], marketId, "moved lookup market id");
    }

    // setMarketFacility
    // given zero principal
    //  when setMarketFacility is called
    //   then it moves lookup without debt dust
    function test_setMarketFacility_givenZeroPrincipal_movesLookupWithoutDebtDust() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(manager);
        floan.setMarketFacility(marketId, otherFacility);

        assertEq(floan.facilityPrincipalDue(facility, debtToken), 0, "old facility principal");
        assertEq(floan.facilityPrincipalDue(otherFacility, debtToken), 0, "new facility principal");
        assertEq(floan.debtTokenPrincipalDue(debtToken), 0, "debt token principal");
    }

    // setMarketFacility
    // given unauthorized manager
    //  when setMarketFacility is called
    //   then it reverts
    function test_setMarketFacility_givenUnauthorizedManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(otherManager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, otherManager)
        );
        floan.setMarketFacility(marketId, otherFacility);
    }

    // setMarketFacility
    // given zero facility
    //  when setMarketFacility is called
    //   then it reverts
    function test_setMarketFacility_givenZeroFacility_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.setMarketFacility(marketId, address(0));
    }
}
