// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

contract GetDepositTokenPeriodsCDEPOTest is CDEPOTest {
    // when the CDEPO has one token
    //  [X] it returns the token periods
    // when the CDEPO has multiple tokens
    //  [X] it returns the tokens periods
    // when the CDEPO has multiple periods for the same deposit and vault token
    //  [X] it returns the tokens periods

    function test_singleToken() public {
        uint8[] memory periods = CDEPO.getDepositTokenPeriods(address(reserveToken));

        assertEq(periods.length, 1, "getDepositTokenPeriods: length");
        assertEq(periods[0], PERIOD_MONTHS, "getDepositTokenPeriods: period");
    }

    function test_multipleTokens() public {
        vm.prank(address(godmode));
        CDEPO.create(iReserveTokenTwoVault, PERIOD_MONTHS + 1, 99e2);

        uint8[] memory periods = CDEPO.getDepositTokenPeriods(address(reserveToken));

        assertEq(periods.length, 1, "getDepositTokenPeriods: length");
        assertEq(periods[0], PERIOD_MONTHS, "getDepositTokenPeriods: period");

        periods = CDEPO.getDepositTokenPeriods(address(iReserveTokenTwo));

        assertEq(periods.length, 1, "getDepositTokenPeriods: length");
        assertEq(periods[0], PERIOD_MONTHS + 1, "getDepositTokenPeriods: period");
    }

    function test_multiplePeriods() public {
        vm.prank(address(godmode));
        CDEPO.create(iReserveTokenVault, PERIOD_MONTHS + 1, 99e2);

        uint8[] memory periods = CDEPO.getDepositTokenPeriods(address(iReserveToken));

        assertEq(periods.length, 2, "getDepositTokenPeriods: length");
        assertEq(periods[0], PERIOD_MONTHS, "getDepositTokenPeriods: period");
        assertEq(periods[1], PERIOD_MONTHS + 1, "getDepositTokenPeriods: period");
    }
}
