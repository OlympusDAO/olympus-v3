// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansAssetActiveDebtOhmTest is BurnerLoansTest {
    // assetActiveDebtOhm
    // given the collateral asset has no Burner Loans market
    //  when its active debt is queried
    //   then it returns zero
    function test_givenAssetIsNotConfigured_returnsZero(address asset_) public view {
        vm.assume(asset_ != address(usds));

        assertEq(burnerLoans.assetActiveDebtOhm(asset_), 0, "unconfigured asset active debt");
    }
}
