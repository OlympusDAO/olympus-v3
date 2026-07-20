// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansTotalActiveDebtOhmTest is BurnerLoansTest {
    function test_givenDebtAcrossMarkets_totalActiveDebtOhm_returnsFacilityDebt() public {
        _addDefaultUsdsAsset();
        burnerLoans.setActiveDebtForTest(address(usds), 0, 40e9);
        _setOtherMarketDebtForTest(60e9);

        assertEq(burnerLoans.totalActiveDebtOhm(), 100e9, "facility debt");
    }
}
