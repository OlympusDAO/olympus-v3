// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANSetMarketFacilityTest is FLOANTest {
    // setMarketFacility
    // given caller without kernel permission
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _expectKernelPermissionRevert(caller_);
        floan.setMarketFacility(marketId, otherFacility);
    }

    // setMarketFacility
    // given invalid market ID
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenInvalidMarket_reverts_fuzz(uint32 marketId_) public {
        vm.assume(marketId_ != 0);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, marketId_));
        floan.setMarketFacility(marketId_, otherFacility);
    }

    // setMarketFacility
    // given caller is the facility but not the market manager
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenCallerIsMarketFacilityButNotManager_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, marketId, facility)
        );
        floan.setMarketFacility(marketId, otherFacility);
    }

    // setMarketFacility
    // given an existing market with outstanding principal
    //  when setMarketFacility is called
    //   then it moves lookup authority and principal
    function test_movesLookupAuthorityAndPrincipal() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.expectEmit(true, true, true, true, address(floan));
        emit IFLOANv1.MarketFacilitySet(marketId, facility, otherFacility);
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
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 0, "old facility principal");
        assertEq(
            floan.getFacilityPrincipalDue(otherFacility, debtToken),
            100e9,
            "new facility principal"
        );
        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "market principal");

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, facility)
        );
        floan.addCollateral(positionId, 1);

        vm.prank(otherFacility);
        assertEq(floan.addCollateral(positionId, 1), 1, "new facility collateral mutation");
    }

    // setMarketFacility
    // given both facilities already service principal for the debt token
    //  when a market is moved between them
    //   then only that market's principal is subtracted and added
    function test_givenPrincipalAtBothFacilities_movesExactMarketAmount_fuzz(
        uint128 movedPrincipal_,
        uint128 retainedPrincipal_,
        uint128 destinationPrincipal_
    ) public {
        movedPrincipal_ = uint128(bound(movedPrincipal_, 1, type(uint128).max));
        retainedPrincipal_ = uint128(bound(retainedPrincipal_, 1, type(uint128).max));
        destinationPrincipal_ = uint128(bound(destinationPrincipal_, 1, type(uint128).max));

        uint32 movedMarket = _createMarket(
            manager,
            facility,
            collateralToken,
            debtToken,
            movedPrincipal_
        );
        uint32 retainedMarket = _createMarket(
            manager,
            facility,
            otherCollateralToken,
            debtToken,
            retainedPrincipal_
        );
        uint32 destinationMarket = _createMarket(
            manager,
            otherFacility,
            collateralToken,
            debtToken,
            destinationPrincipal_
        );
        _createPositionWithDebt(movedMarket, facility, borrower, movedPrincipal_);
        _createPositionWithDebt(retainedMarket, facility, otherBorrower, retainedPrincipal_);
        _createPositionWithDebt(destinationMarket, otherFacility, borrower, destinationPrincipal_);

        vm.prank(manager);
        floan.setMarketFacility(movedMarket, otherFacility);

        assertEq(
            floan.getFacilityPrincipalDue(facility, debtToken),
            retainedPrincipal_,
            "source retains other market principal"
        );
        assertEq(
            floan.getFacilityPrincipalDue(otherFacility, debtToken),
            uint256(destinationPrincipal_) + movedPrincipal_,
            "destination adds moved market principal"
        );
    }

    // setMarketFacility
    // given duplicate target pair
    //  when setMarketFacility is called
    //   then it indexes both markets
    function test_givenDuplicateTargetPair_indexesBothMarkets() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 existingMarketId = _createMarket(
            manager,
            otherFacility,
            collateralToken,
            debtToken,
            1_000e9
        );
        vm.startPrank(facility);
        uint64 movedPositionId = floan.createPosition(marketId, borrower);
        floan.addCollateral(movedPositionId, 150e18);
        floan.increaseDebt(movedPositionId, 100e9, 10e9, uint48(block.timestamp + 30 days));
        vm.stopPrank();
        vm.startPrank(otherFacility);
        uint64 existingPositionId = floan.createPosition(existingMarketId, otherBorrower);
        floan.addCollateral(existingPositionId, 250e18);
        floan.increaseDebt(existingPositionId, 200e9, 20e9, uint48(block.timestamp + 30 days));
        vm.stopPrank();

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
        assertEq(floan.getPosition(movedPositionId).collateral, 150e18, "moved collateral");
        assertEq(floan.getPosition(movedPositionId).principalDue, 100e9, "moved principal");
        assertEq(floan.getPosition(movedPositionId).interestDue, 10e9, "moved interest");
        assertEq(floan.getPosition(existingPositionId).collateral, 250e18, "existing collateral");
        assertEq(floan.getPosition(existingPositionId).principalDue, 200e9, "existing principal");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 0, "source principal");
        assertEq(
            floan.getFacilityPrincipalDue(otherFacility, debtToken),
            300e9,
            "destination principal"
        );
        assertEq(floan.getMarketInterestDue(marketId), 10e9, "moved market interest");
        assertEq(floan.getMarketInterestDue(existingMarketId), 20e9, "existing market interest");
    }

    // setMarketFacility
    // given zero principal
    //  when setMarketFacility is called
    //   then it moves lookup without debt dust
    function test_givenZeroPrincipal_movesLookupWithoutDebtDust() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(manager);
        floan.setMarketFacility(marketId, otherFacility);

        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 0, "old facility principal");
        assertEq(
            floan.getFacilityPrincipalDue(otherFacility, debtToken),
            0,
            "new facility principal"
        );
    }

    // setMarketFacility
    // given the requested facility is already assigned
    //  when the manager sets the facility
    //   then it is a no-op
    function test_givenExistingFacility_doesNotChangeAccountingOrIndexes() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createPositionWithDebt(marketId, facility, borrower, 100e9);

        vm.prank(manager);
        floan.setMarketFacility(marketId, facility);

        uint256[] memory marketIds = floan.getMarketIds(facility, collateralToken, debtToken);
        assertEq(marketIds.length, 1, "lookup count");
        assertEq(marketIds[0], marketId, "lookup market id");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 100e9, "facility principal");
        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "market principal");
    }

    // setMarketFacility
    // given unauthorized manager
    //  when setMarketFacility is called
    //   then it reverts
    function test_givenUnauthorizedManager_reverts() public {
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
    function test_givenZeroFacility_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.setMarketFacility(marketId, address(0));
    }
}
