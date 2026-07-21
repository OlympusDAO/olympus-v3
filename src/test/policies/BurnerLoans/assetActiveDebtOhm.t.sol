// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansAssetActiveDebtOhmTest is BurnerLoansTest {
    // assetActiveDebtOhm
    // given debt across markets
    //  when assetActiveDebtOhm is called
    //   then it returns only requested market debt
    function test_givenDebtAcrossMarkets_assetActiveDebtOhm_returnsOnlyRequestedMarketDebt()
        public
    {
        _addDefaultUsdsAsset();
        burnerLoans.setActiveDebtForTest(address(usds), 0, 40e9);
        _setOtherMarketDebtForTest(60e9);

        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), 40e9, "asset debt");
    }
}
