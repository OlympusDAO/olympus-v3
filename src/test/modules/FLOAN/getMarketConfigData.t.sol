// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANGetMarketConfigDataTest is FLOANTest {
    // getMarketConfigData
    // given existing market
    //  when getMarketConfigData is called
    //   then it returns opaque bytes
    function test_givenExistingMarket_getMarketConfigData_returnsOpaqueBytes() public {
        bytes memory expected = abi.encode("product config", uint256(42));
        vm.prank(manager);
        uint32 marketId = floan.createMarket(
            _market(manager, facility, collateralToken, debtToken, 1_000e9),
            expected
        );

        assertEq(floan.getMarketConfigData(marketId), expected, "config data");
    }

    // getMarketConfigData
    // given missing market
    //  when getMarketConfigData is called
    //   then it reverts
    function test_givenMissingMarket_getMarketConfigData_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, 0));
        floan.getMarketConfigData(0);
    }
}
