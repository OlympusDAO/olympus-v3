// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

contract GetDepositTokensCDEPOTest is CDEPOTest {
    // when the CDEPO has no tokens
    //  [ ] it returns an empty array
    // when the CDEPO has one token
    //  [X] it returns the token
    // when the CDEPO has multiple tokens
    //  [X] it returns the tokens
    // when the CDEPO has multiple periods for the same deposit and vault token
    //  [X] it returns the tokens

    function test_singleToken() public {
        IConvertibleDepository.DepositToken[] memory tokens = CDEPO.getDepositTokens();

        assertEq(tokens.length, 1, "getTokens: length");
        assertEq(address(tokens[0].token), address(reserveToken), "getTokens: token");
        assertEq(tokens[0].periods.length, 1, "getTokens: periods length");
        assertEq(tokens[0].periods[0], PERIOD_MONTHS, "getTokens: period");
    }

    function test_multipleTokens() public {
        vm.prank(address(godmode));
        CDEPO.create(iReserveTokenTwoVault, PERIOD_MONTHS, 99e2);

        IConvertibleDepository.DepositToken[] memory tokens = CDEPO.getDepositTokens();

        assertEq(tokens.length, 2, "getTokens: length");
        assertEq(address(tokens[0].token), address(reserveToken), "getTokens: reserveToken");
        assertEq(tokens[0].periods.length, 1, "getTokens: periods length");
        assertEq(tokens[0].periods[0], PERIOD_MONTHS, "getTokens: period");

        assertEq(
            address(tokens[1].token),
            address(iReserveTokenTwo),
            "getTokens: iReserveTokenTwo"
        );
        assertEq(tokens[1].periods.length, 1, "getTokens: periods length");
        assertEq(tokens[1].periods[0], PERIOD_MONTHS, "getTokens: period");
    }

    function test_multiplePeriods() public {
        vm.prank(address(godmode));
        CDEPO.create(iReserveTokenVault, PERIOD_MONTHS + 1, 99e2);

        IConvertibleDepository.DepositToken[] memory tokens = CDEPO.getDepositTokens();

        assertEq(tokens.length, 1, "getTokens: length");
        assertEq(address(tokens[0].token), address(iReserveToken), "getTokens: token");
        assertEq(tokens[0].periods.length, 2, "getTokens: periods length");
        assertEq(tokens[0].periods[0], PERIOD_MONTHS, "getTokens: period");
        assertEq(tokens[0].periods[1], PERIOD_MONTHS + 1, "getTokens: period");
    }
}
