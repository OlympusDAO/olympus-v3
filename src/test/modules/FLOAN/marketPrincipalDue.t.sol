// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {FLOANTest} from "src/test/modules/FLOAN/FLOANTest.sol";

contract FLOANMarketPrincipalDueTest is FLOANTest {
    function test_givenMarketDebt_marketPrincipalDue_returnsOnlyThatMarketDebt() public {
        uint32 first = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        uint32 second = _createMarket(manager, facility, collateralToken, debtToken, 1_000e9);
        _createPositionWithDebt(first, facility, borrower, 100e9);
        _createPositionWithDebt(second, facility, borrower, 200e9);

        assertEq(floan.marketPrincipalDue(first), 100e9, "first market principal");
        assertEq(floan.marketPrincipalDue(second), 200e9, "second market principal");
    }

    function test_givenMissingMarket_marketPrincipalDue_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, 0));
        floan.marketPrincipalDue(0);
    }
}
