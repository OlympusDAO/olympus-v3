// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetMarketTest is FLOANTest {
    function test_givenExistingMarket_getMarket_returnsEveryStoredField() public {
        IFLOANv1.Market memory expected = _market(
            manager,
            facility,
            collateralToken,
            debtToken,
            1_000e9
        );
        vm.prank(manager);
        uint32 marketId = floan.createMarket(expected, hex"1234");

        assertEq(abi.encode(floan.getMarket(marketId)), abi.encode(expected), "market");
    }

    function test_givenMissingMarket_getMarket_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, 0));
        floan.getMarket(0);
    }
}
