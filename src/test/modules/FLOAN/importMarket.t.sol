// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Module} from "src/Kernel.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANImportMarketTest is FLOANTest {
    // importMarket
    // given the caller lacks Kernel permission
    //  when a market is imported
    //   then it reverts
    function test_givenCallerWithoutKernelPermission_importMarket_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );
        floan.importMarket(
            0,
            _market(manager, facility, collateralToken, debtToken, 1_000e9),
            hex""
        );
    }

    // importMarket
    // given the imported ID is not the next contiguous market ID
    //  when a market is imported
    //   then it reverts
    function test_givenNonContiguousId_importMarket_reverts() public {
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidImportId.selector, 0, 1));
        floan.importMarket(
            1,
            _market(manager, facility, collateralToken, debtToken, 1_000e9),
            hex""
        );
    }

    // importMarket
    // given an existing market
    //  when the following contiguous market is imported
    //   then it preserves the imported ID
    //   then it stores configuration and lookup indexes
    function test_givenExistingMarket_importMarket_preservesContiguousIdAndIndexes() public {
        _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        IFLOANv1.Market memory imported = _market(
            otherManager,
            otherFacility,
            otherCollateralToken,
            otherDebtToken,
            2_000e9
        );

        vm.expectEmit(true, false, false, true, address(floan));
        emit IFLOANv1.MarketImported(1);
        vm.prank(manager);
        floan.importMarket(1, imported, abi.encode(uint256(456)));

        IFLOANv1.Market memory stored = floan.getMarket(1);
        uint256[] memory lookupIds = floan.getMarketIds(
            otherFacility,
            otherCollateralToken,
            otherDebtToken
        );
        assertEq(floan.marketCount(), 2, "market count");
        assertEq(stored.manager, otherManager, "manager");
        assertEq(stored.facility, otherFacility, "facility");
        assertEq(abi.decode(floan.getMarketConfigData(1), (uint256)), 456, "config data");
        assertEq(lookupIds.length, 1, "lookup count");
        assertEq(lookupIds[0], 1, "lookup market id");
    }
}
