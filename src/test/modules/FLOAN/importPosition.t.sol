// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Module} from "src/Kernel.sol";
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
    function test_givenCallerWithoutKernelPermission_importPosition_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.importPosition(0, _activePosition(borrower, 100e9), 0);
    }

    // importPosition
    // given the imported ID is not the next contiguous position ID
    //  when a position is imported
    //   then it reverts
    function test_givenNonContiguousId_importPosition_reverts() public {
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidImportId.selector, 0, 1));
        floan.importPosition(1, _activePosition(borrower, 100e9), 0);
    }

    // importPosition
    // given an active position from a previous ledger
    //  when it is imported
    //   then it preserves the position ID and values
    //   then it reconstructs all indexes and principal aggregates
    function test_givenActivePosition_importPosition_reconstructsState() public {
        IFLOANv1.Position memory imported = _activePosition(borrower, 80e9);

        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.PositionImported(0, 0);
        vm.prank(manager);
        floan.importPosition(0, imported, 0);

        IFLOANv1.Position memory stored = floan.getPosition(0);
        assertEq(abi.encode(stored), abi.encode(imported), "position");
        assertEq(floan.positionCount(), 1, "position count");
        assertEq(floan.marketPrincipalDue(marketId), 80e9, "market principal");
        assertEq(floan.facilityPrincipalDue(facility, debtToken), 80e9, "facility principal");
        assertEq(floan.debtTokenPrincipalDue(debtToken), 80e9, "debt token principal");
        assertEq(floan.activeBorrowerCount(marketId), 1, "active borrower count");
        assertEq(floan.activeBorrowerAt(marketId, 0), borrower, "active borrower");
        assertEq(floan.getPositionIdsForMarketAndBorrower(marketId, borrower)[0], 0, "pair index");
    }

    // importPosition
    // given two active positions for the same market and borrower
    //  when both are imported in order
    //   then it preserves both positions
    //   then it indexes the borrower once
    //   then it aggregates both principal balances
    function test_givenMultipleActivePositions_importPosition_preservesGenericMultiplicity()
        public
    {
        vm.startPrank(manager);
        floan.importPosition(0, _activePosition(borrower, 80e9), 0);
        floan.importPosition(1, _activePosition(borrower, 20e9), 0);
        vm.stopPrank();

        assertEq(floan.positionCount(), 2, "position count");
        assertEq(
            floan.getPositionIdsForMarketAndBorrower(marketId, borrower).length,
            2,
            "pair position count"
        );
        assertEq(floan.activeBorrowerCount(marketId), 1, "active borrower count");
        assertEq(floan.marketPrincipalDue(marketId), 100e9, "market principal");
    }

    // importPosition
    // given a previously defaulted position
    //  when it is imported
    //   then it remains inactive
    //   then it reconstructs defaulted principal aggregates
    function test_givenDefaultedPosition_importPosition_reconstructsDefaultAggregates() public {
        IFLOANv1.Position memory imported = _activePosition(borrower, 0);
        imported.collateral = 0;
        imported.principalDue = 0;
        imported.interestDue = 0;
        imported.defaulted = true;

        vm.prank(manager);
        floan.importPosition(0, imported, 80e9);

        assertTrue(floan.getPosition(0).defaulted, "position defaulted");
        assertEq(floan.activeBorrowerCount(marketId), 0, "active borrower count");
        assertEq(floan.marketPrincipalDue(marketId), 0, "active market principal");
        assertEq(floan.marketPrincipalDefaulted(marketId), 80e9, "market defaulted");
        assertEq(floan.facilityPrincipalDefaulted(facility, debtToken), 80e9, "facility defaulted");
        assertEq(floan.debtTokenPrincipalDefaulted(debtToken), 80e9, "debt token defaulted");
    }

    // importPosition
    // given a non-defaulted position with a defaulted principal amount
    //  when it is imported
    //   then it reverts
    function test_givenInconsistentDefaultData_importPosition_reverts() public {
        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.importPosition(0, _activePosition(borrower, 80e9), 1);
    }

    // importPosition
    // given defaulted principal above principal drawn
    //  when importPosition is called
    //   then it reverts
    function test_givenDefaultedPrincipalAbovePrincipalDrawn_importPosition_reverts() public {
        IFLOANv1.Position memory imported = _activePosition(borrower, 0);
        imported.collateral = 0;
        imported.principalDue = 0;
        imported.interestDue = 0;
        imported.defaulted = true;

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.importPosition(0, imported, imported.principalDrawn + 1);
    }

    // importPosition
    // given active position without maturity
    //  when importPosition is called
    //   then it reverts
    function test_givenActivePositionWithoutMaturity_importPosition_reverts() public {
        IFLOANv1.Position memory imported = _activePosition(borrower, 80e9);
        imported.maturity = 0;

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.importPosition(0, imported, 0);
    }

    // importPosition
    // given closed position with active episode data
    //  when importPosition is called
    //   then it reverts
    function test_givenClosedPositionWithActiveEpisodeData_importPosition_reverts() public {
        IFLOANv1.Position memory imported = _activePosition(borrower, 0);

        vm.prank(manager);
        vm.expectRevert(IFLOANv1.FLOAN_InvalidConfig.selector);
        floan.importPosition(0, imported, 0);
    }

    // importPosition
    // given active imported principal would exceed the market cap
    //  when the position is imported
    //   then it reverts
    function test_givenPrincipalAboveMarketCap_importPosition_reverts() public {
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_PrincipalCapExceeded.selector, marketId, 1_000e9)
        );
        floan.importPosition(0, _activePosition(borrower, 1_001e9), 0);
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
                lastBorrowBlock: uint32(block.number - 1),
                defaulted: false
            });
    }
}
