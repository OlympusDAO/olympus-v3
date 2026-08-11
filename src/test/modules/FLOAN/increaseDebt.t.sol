// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANIncreaseDebtTest is FLOANTest {
    // increaseDebt
    // given caller without kernel permission
    //  when increaseDebt is called
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        _expectKernelPermissionRevert(caller_);
        floan.increaseDebt(positionId, 1, 0, uint48(block.timestamp + 1));
    }

    // increaseDebt
    // given invalid position ID
    //  when increaseDebt is called
    //   then it reverts
    function test_givenInvalidPosition_reverts_fuzz(uint64 positionId_) public {
        vm.assume(positionId_ != 0);
        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidPosition.selector, positionId_)
        );
        floan.increaseDebt(positionId_, 1, 0, uint48(block.timestamp + 1));
    }

    // increaseDebt
    // given caller is not the position market facility
    //  when increaseDebt is called
    //   then it reverts
    function test_givenCallerIsNotPositionMarketFacility_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.prank(otherFacility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotFacility.selector, marketId, otherFacility)
        );
        floan.increaseDebt(positionId, 1, 0, uint48(block.timestamp + 1));
    }

    // increaseDebt
    // given originations disabled
    //  when increaseDebt is called
    //   then it reverts without state change
    function test_givenOriginationsDisabled_revertsWithoutStateChange() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);
        vm.prank(manager);
        floan.setMarketOriginationsEnabled(marketId, false);

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_OriginationsDisabled.selector, marketId)
        );
        floan.increaseDebt(positionId, 1, 0, uint48(block.timestamp + 1));
        assertEq(floan.getPosition(positionId).principalDue, 0, "principal unchanged");
        assertEq(floan.getMarketPrincipalDue(marketId), 0, "market principal unchanged");
    }

    // increaseDebt
    // given a position whose previous episode defaulted
    //  when increaseDebt is called
    //   then it starts a new debt episode on the same position ID
    function test_givenDefaultedPosition_startsNewEpisode() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        uint48 maturity = uint48(block.timestamp + 60 days);

        vm.startPrank(facility);
        floan.defaultPosition(positionId);
        floan.increaseDebt(positionId, 1, 0, maturity);
        vm.stopPrank();

        IFLOANv1.Position memory position = floan.getPosition(positionId);
        assertEq(position.principalDrawn, 1, "new principal drawn");
        assertEq(position.principalDue, 1, "new principal due");
        assertEq(position.maturity, maturity, "new maturity");
        assertEq(floan.getPositionCount(), 1, "position ID reused");
    }

    // increaseDebt
    // given zero principal and zero interest
    //  when increaseDebt is called
    //   then it reverts
    function test_givenZeroPrincipalAndInterest_reverts() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);

        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.increaseDebt(positionId, 0, 0, uint48(block.timestamp + 1));
    }

    // increaseDebt
    // given no active debt and interest-only increase
    //  when increaseDebt is called
    //   then it reverts
    function test_givenNoActiveDebt_givenInterestOnly_reverts_fuzz(uint128 interest_) public {
        interest_ = uint128(bound(interest_, 1, type(uint128).max));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);

        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.increaseDebt(positionId, 0, interest_, uint48(block.timestamp + 1));
    }

    // increaseDebt
    // given maturity at or before current timestamp
    //  when increaseDebt is called
    //   then it reverts
    function test_givenInvalidMaturity_reverts_fuzz(uint48 maturity_) public {
        maturity_ = uint48(bound(maturity_, 0, block.timestamp));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPosition(marketId, facility, borrower);

        vm.prank(facility);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidAmount.selector);
        floan.increaseDebt(positionId, 1, 0, maturity_);
    }

    // increaseDebt
    // given active debt
    //  when increaseDebt is called
    //   then it requires existing maturity
    function test_givenActiveDebt_requiresExistingMaturity_fuzz(uint48 requestedMaturity_) public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        uint48 maturity = floan.getPosition(positionId).maturity;
        requestedMaturity_ = uint48(
            bound(requestedMaturity_, block.timestamp + 1, type(uint48).max)
        );
        vm.assume(requestedMaturity_ != maturity);

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFLOANv1.FLOAN_InvalidMaturity.selector,
                maturity,
                requestedMaturity_
            )
        );
        floan.increaseDebt(positionId, 1, 0, requestedMaturity_);
        assertEq(floan.getPosition(positionId).principalDue, 100e9, "principal unchanged");
    }

    // increaseDebt
    // given principal debt is increased
    //  when increaseDebt is called
    //   then it updates market and facility principal totals
    function test_updatesMarketAndFacilityPrincipalTotals() public {
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

        assertEq(floan.getActiveBorrowerCount(firstMarket), 1, "first market borrower count");
        assertEq(floan.getActiveBorrowerAt(firstMarket, 0), borrower, "first market borrower");
        assertEq(floan.getMarketPrincipalDue(firstMarket), 100e9, "first market principal");
        assertEq(floan.getMarketPrincipalDue(secondMarket), 200e9, "second market principal");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 300e9, "facility principal");
        assertEq(
            floan.getFacilityPrincipalDue(otherFacility, debtToken),
            400e9,
            "other facility principal"
        );
    }

    // increaseDebt
    // given an initial draw with deferred interest
    //  when increaseDebt is called
    //   then deferred interest does not affect principal totals
    function test_givenInitialDrawWithDeferredInterest_updatesOnlyPrincipalTotals() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);

        vm.startPrank(facility);
        uint64 positionId = floan.createPosition(marketId, borrower);
        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionDebtIncreased(
            positionId,
            100e9,
            100e9,
            25e9,
            uint48(block.timestamp + 30 days)
        );
        floan.increaseDebt(positionId, 100e9, 25e9, uint48(block.timestamp + 30 days));
        vm.stopPrank();

        assertEq(floan.getPosition(positionId).lastBorrowBlock, block.number, "last borrow block");
        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "market principal");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 100e9, "facility principal");
        assertEq(floan.getMarketInterestDue(marketId), 25e9, "market interest");
    }

    // increaseDebt
    // given active debt
    //  when deferred interest is added without principal
    //   then it updates only interest and preserves debt episode metadata
    function test_givenActiveDebt_addsInterestWithoutPrincipal_fuzz(uint128 interest_) public {
        interest_ = uint128(bound(interest_, 1, type(uint128).max));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 100e9);
        uint64 positionId = _createPositionWithDebt(marketId, facility, borrower, 100e9);
        IFLOANv1.Position memory before_ = floan.getPosition(positionId);

        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionDebtIncreased(
            positionId,
            before_.principalDrawn,
            before_.principalDue,
            interest_,
            before_.maturity
        );
        vm.prank(facility);
        floan.increaseDebt(positionId, 0, interest_, before_.maturity);

        IFLOANv1.Position memory after_ = floan.getPosition(positionId);
        assertEq(after_.principalDrawn, before_.principalDrawn, "principal drawn");
        assertEq(after_.principalDue, before_.principalDue, "principal due");
        assertEq(after_.interestDue, interest_, "interest due");
        assertEq(after_.maturity, before_.maturity, "maturity");
        assertEq(after_.lastBorrowBlock, before_.lastBorrowBlock, "last principal increase block");
        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "market principal");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 100e9, "facility principal");
        assertEq(floan.getMarketInterestDue(marketId), interest_, "market interest");
    }

    // increaseDebt
    // given a fuzzed principal increase
    //  when increaseDebt is called
    //   then it updates each principal total
    function test_updatesEachPrincipalTotal_fuzz(uint128 principal_) public {
        principal_ = uint128(bound(principal_, 1, type(uint128).max));
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, principal_);

        _createPositionWithDebt(marketId, facility, borrower, principal_);

        assertEq(floan.getMarketPrincipalDue(marketId), principal_, "market principal");
        assertEq(
            floan.getFacilityPrincipalDue(facility, debtToken),
            principal_,
            "facility principal"
        );
    }

    // increaseDebt
    // given an empty market
    //  when increaseDebt is called
    //   then any first draw up to the cap succeeds
    function test_givenStartingDebt_borrowsUpToCap_fuzz(
        uint128 principalCap_,
        uint128 principal_
    ) public {
        principalCap_ = uint128(bound(principalCap_, 1, type(uint128).max));
        principal_ = uint128(bound(principal_, 1, principalCap_));
        uint32 marketId = _createMarket(
            manager,
            facility,
            collateralToken,
            debtToken,
            principalCap_
        );

        _createPositionWithDebt(marketId, facility, borrower, principal_);

        assertEq(floan.getMarketPrincipalDue(marketId), principal_, "market principal");
        assertEq(
            floan.getFacilityPrincipalDue(facility, debtToken),
            principal_,
            "facility principal"
        );
    }

    // increaseDebt
    // given market principal is at the cap
    //  when any additional principal is added
    //   then it reverts
    function test_givenMarketAtCap_additionalDebtReverts_fuzz(uint128 additionalPrincipal_) public {
        additionalPrincipal_ = uint128(bound(additionalPrincipal_, 1, type(uint128).max));
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
        floan.increaseDebt(positionId, additionalPrincipal_, 0, uint48(block.timestamp + 30 days));

        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "market principal unchanged");
        assertEq(
            floan.getFacilityPrincipalDue(facility, debtToken),
            100e9,
            "facility principal unchanged"
        );
    }

    // increaseDebt
    // given market principal below the cap
    //  when additional principal would cross the cap
    //   then it reverts
    function test_givenExistingDebt_additionalDebtAboveCapReverts_fuzz(
        uint128 existingPrincipal_,
        uint128 excess_
    ) public {
        existingPrincipal_ = uint128(bound(existingPrincipal_, 1, 99e9));
        excess_ = uint128(bound(excess_, 1, type(uint128).max - 100e9));
        uint128 additionalPrincipal = uint128(100e9 - existingPrincipal_ + excess_);
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 100e9);
        uint64 positionId = _createPositionWithDebt(
            marketId,
            facility,
            borrower,
            existingPrincipal_
        );

        vm.prank(facility);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFLOANv1.FLOAN_PrincipalCapExceeded.selector,
                marketId,
                uint128(100e9)
            )
        );
        floan.increaseDebt(positionId, additionalPrincipal, 0, uint48(block.timestamp + 30 days));

        assertEq(floan.getMarketPrincipalDue(marketId), existingPrincipal_, "market principal");
    }

    // increaseDebt
    // given markets with different debt tokens in one facility
    //  when increaseDebt is called
    //   then it isolates debt tokens within facility
    function test_isolatesDebtTokensWithinFacility() public {
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

        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 100e9, "first token total");
        assertEq(
            floan.getFacilityPrincipalDue(facility, otherDebtToken),
            200e9,
            "second token total"
        );
    }

    // increaseDebt
    // given multiple positions for distinct borrowers
    //  when debt is increased for each position
    //   then active borrower getters contain each borrower only once
    function test_givenMultiplePositions_updatesActiveBorrowerGettersWithoutDuplicates() public {
        uint32 marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createPositionWithDebt(marketId, facility, borrower, 100e9);
        _createPositionWithDebt(marketId, facility, borrower, 100e9);
        _createPositionWithDebt(marketId, facility, otherBorrower, 200e9);

        address[] memory activeBorrowers = floan.getActiveBorrowers(marketId);
        assertEq(activeBorrowers.length, 2, "active borrower array length");
        assertEq(floan.getActiveBorrowerCount(marketId), 2, "active borrower count");
        assertEq(floan.getActiveBorrowerAt(marketId, 0), borrower, "first active borrower");
        assertEq(floan.getActiveBorrowerAt(marketId, 1), otherBorrower, "second active borrower");

        vm.expectRevert(IFLOANv1.FLOAN_ActiveBorrowerIndexOutOfBounds.selector);
        floan.getActiveBorrowerAt(marketId, 2);
    }
}
