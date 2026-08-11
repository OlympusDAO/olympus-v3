// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANImportPositionTest is FLOANTest {
    uint32 internal marketId;

    function setUp() public override {
        super.setUp();
        marketId = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
    }

    // importPosition
    // given the caller lacks Kernel permission
    //  when a position is imported
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_reverts_fuzz(address caller_) public {
        _expectKernelPermissionRevert(caller_);
        floan.importPosition(0, _activePosition(borrower, 100e9), 0);
    }

    // importPosition
    // given the imported ID is not the next contiguous position ID
    //  when a position is imported
    //   then it reverts
    function test_givenNonContiguousId_reverts_fuzz(uint64 positionId_) public {
        positionId_ = uint64(bound(positionId_, 1, type(uint64).max));
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidImportId.selector, 0, positionId_)
        );
        floan.importPosition(positionId_, _activePosition(borrower, 100e9), 0);
    }

    // importPosition
    // given the position references an invalid market
    //  when it is imported
    //   then it reverts without consuming the ID
    function test_givenInvalidMarket_reverts() public {
        IFLOANv1.Position memory imported = _activePosition(borrower, 100e9);
        imported.marketId = marketId + 1;

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, imported.marketId)
        );
        floan.importPosition(0, imported, 0);

        assertEq(floan.getPositionCount(), 0, "position id not consumed");
    }

    // importPosition
    // given the borrower is zero
    //  when it is imported
    //   then it reverts without consuming the ID
    function test_givenZeroBorrower_reverts() public {
        IFLOANv1.Position memory imported = _activePosition(address(0), 100e9);

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_ZeroAddress.selector);
        floan.importPosition(0, imported, 0);

        assertEq(floan.getPositionCount(), 0, "position id not consumed");
    }

    // importPosition
    // given an active position from a previous ledger
    //  when it is imported
    //   then it preserves the position ID and values
    //   then it reconstructs all indexes and principal aggregates
    function test_givenActivePositionWithPrincipalAndInterest_reconstructsState() public {
        IFLOANv1.Position memory imported = _activePosition(borrower, 80e9);

        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionImported(0, 0);
        vm.prank(manager);
        floan.importPosition(0, imported, 0);

        _assertPosition(0, imported);
        _assertPositionIndexes(0, marketId, borrower, 1, 1, 1, 1);
        assertEq(floan.getMarketPrincipalDue(marketId), 80e9, "market principal");
        assertEq(floan.getMarketCollateral(marketId), 150e18, "market collateral");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 80e9, "facility principal");
        assertEq(floan.getMarketInterestDue(marketId), 5e9, "market interest");
        assertEq(floan.getActiveBorrowerCount(marketId), 1, "active borrower count");
        assertEq(floan.getActiveBorrowerAt(marketId, 0), borrower, "active borrower");
    }

    // importPosition
    // given principal was repaid but deferred interest remains
    //  when the position is imported
    //   then it reconstructs interest accounting and active membership
    function test_givenInterestOnlyActivePosition_reconstructsState() public {
        IFLOANv1.Position memory imported = _activePosition(borrower, 0);
        imported.interestDue = 25e9;

        vm.prank(manager);
        floan.importPosition(0, imported, 0);

        _assertPosition(0, imported);
        assertEq(floan.getMarketPrincipalDue(marketId), 0, "market principal");
        assertEq(floan.getFacilityPrincipalDue(facility, debtToken), 0, "facility principal");
        assertEq(floan.getMarketInterestDue(marketId), 25e9, "market interest");
        assertEq(floan.getActiveBorrowerCount(marketId), 1, "active borrower count");
        assertEq(floan.getActiveBorrowerAt(marketId, 0), borrower, "active borrower");
    }

    // importPosition
    // given two active positions for the same market and borrower
    //  when both are imported in order
    //   then it preserves both positions
    //   then it indexes the borrower once
    //   then it aggregates both principal balances
    function test_givenMultipleActivePositions_preservesGenericMultiplicity() public {
        vm.startPrank(manager);
        floan.importPosition(0, _activePosition(borrower, 80e9), 0);
        floan.importPosition(1, _activePosition(borrower, 20e9), 0);
        vm.stopPrank();

        assertEq(floan.getPositionCount(), 2, "position count");
        assertEq(
            floan.getPositionIdsForMarketAndBorrower(marketId, borrower).length,
            2,
            "pair position count"
        );
        assertEq(floan.getActiveBorrowerCount(marketId), 1, "active borrower count");
        assertEq(floan.getMarketPrincipalDue(marketId), 100e9, "market principal");
        assertEq(floan.getMarketInterestDue(marketId), 10e9, "market interest");
        assertEq(floan.getMarketCollateral(marketId), 300e18, "market collateral");
    }

    // importPosition
    // given a reusable position with historical defaulted principal
    //  when it is imported
    //   then it remains inactive
    //   then it reconstructs defaulted principal aggregates
    function test_givenReusablePositionWithDefaultHistory_reconstructsDefaultAggregates() public {
        IFLOANv1.Position memory imported = _closedPosition(borrower);

        vm.prank(manager);
        floan.importPosition(0, imported, 80e9);

        _assertPosition(0, imported);
        assertEq(floan.getActiveBorrowerCount(marketId), 0, "active borrower count");
        assertEq(floan.getMarketPrincipalDue(marketId), 0, "active market principal");
        assertEq(floan.getMarketPrincipalDefaulted(marketId), 80e9, "market defaulted");
    }

    // importPosition
    // given an active reused position with historical defaulted principal
    //  when it is imported
    //   then it reconstructs both live and historical accounting
    function test_givenActiveReusedPositionWithDefaultHistory_reconstructsBothAggregates() public {
        vm.prank(manager);
        floan.importPosition(0, _activePosition(borrower, 80e9), 120e9);

        assertEq(floan.getMarketPrincipalDue(marketId), 80e9, "live principal");
        assertEq(floan.getMarketPrincipalDefaulted(marketId), 120e9, "historical default");
        assertEq(floan.getActiveBorrowerCount(marketId), 1, "active borrower count");
    }

    // importPosition
    // given principal due exceeds principal drawn
    //  when it is imported
    //   then it reverts
    function test_givenPrincipalDueAbovePrincipalDrawn_reverts() public {
        IFLOANv1.Position memory imported = _activePosition(borrower, 100e9);
        imported.principalDrawn = imported.principalDue - 1;

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.importPosition(0, imported, 0);
    }

    // importPosition
    // given active position without maturity
    //  when importPosition is called
    //   then it reverts
    function test_givenActivePositionWithoutMaturity_reverts() public {
        IFLOANv1.Position memory imported = _activePosition(borrower, 80e9);
        imported.maturity = 0;

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.importPosition(0, imported, 0);
    }

    // importPosition
    // given a closed position retains principal drawn
    //  when importPosition is called
    //   then it reverts
    function test_givenClosedPositionWithPrincipalDrawn_reverts() public {
        IFLOANv1.Position memory imported = _closedPosition(borrower);
        imported.principalDrawn = 1;

        _expectInvalidConfig(imported, 0);
    }

    // importPosition
    // given a closed position retains a maturity
    //  when importPosition is called
    //   then it reverts
    function test_givenClosedPositionWithMaturity_reverts() public {
        IFLOANv1.Position memory imported = _closedPosition(borrower);
        imported.maturity = 1;

        _expectInvalidConfig(imported, 0);
    }

    // importPosition
    // given a closed position retains a last borrow block
    //  when importPosition is called
    //   then it reverts
    function test_givenClosedPositionWithLastBorrowBlock_reverts() public {
        IFLOANv1.Position memory imported = _closedPosition(borrower);
        imported.lastBorrowBlock = 1;

        _expectInvalidConfig(imported, 0);
    }

    // importPosition
    // given a fully closed position
    //  when it is imported
    //   then it preserves the ID and indexes without affecting aggregates
    function test_givenClosedPosition_importsWithoutActiveAccounting() public {
        IFLOANv1.Position memory imported = _closedPosition(borrower);
        imported.collateral = 50e18;

        vm.prank(manager);
        floan.importPosition(0, imported, 0);

        assertEq(floan.getPositionCount(), 1, "position count");
        assertEq(floan.getPosition(0).collateral, 50e18, "collateral preserved");
        assertEq(floan.getMarketCollateral(marketId), 50e18, "market collateral");
        assertEq(floan.getActiveBorrowerCount(marketId), 0, "no active borrower");
        assertEq(floan.getMarketPrincipalDue(marketId), 0, "no live principal");
    }

    // importPosition
    // given active imported principal would exceed the market cap
    //  when the position is imported
    //   then it reverts
    function test_givenPrincipalAboveMarketCap_reverts() public {
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_PrincipalCapExceeded.selector, marketId, 1_000e9)
        );
        floan.importPosition(0, _activePosition(borrower, 1_001e9), 0);
    }

    // importPosition
    // given active imported principal equals the market cap
    //  when the position is imported
    //   then it succeeds at the boundary
    function test_givenPrincipalAtMarketCap_succeeds() public {
        vm.prank(manager);
        floan.importPosition(0, _activePosition(borrower, 1_000e9), 0);

        assertEq(floan.getMarketPrincipalDue(marketId), 1_000e9, "market principal at cap");
    }

    function _activePosition(
        address borrower_,
        uint128 principalDue_
    ) internal view returns (IFLOANv1.Position memory) {
        return
            IFLOANv1.Position({
                borrower: borrower_,
                marketId: marketId,
                collateral: 150e18,
                principalDrawn: principalDue_ > 100e9 ? principalDue_ : 100e9,
                principalDue: principalDue_,
                interestDue: principalDue_ == 0 ? 0 : 5e9,
                maturity: uint48(block.timestamp - 1),
                lastBorrowBlock: uint32(block.number - 1)
            });
    }

    function _closedPosition(address borrower_) internal view returns (IFLOANv1.Position memory) {
        return
            IFLOANv1.Position({
                borrower: borrower_,
                marketId: marketId,
                collateral: 0,
                principalDrawn: 0,
                principalDue: 0,
                interestDue: 0,
                maturity: 0,
                lastBorrowBlock: 0
            });
    }

    function _expectInvalidConfig(
        IFLOANv1.Position memory position_,
        uint128 principalDefaulted_
    ) internal {
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.importPosition(0, position_, principalDefaulted_);
    }
}
