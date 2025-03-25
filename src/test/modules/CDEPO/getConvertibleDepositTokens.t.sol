// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

contract GetConvertibleDepositTokensCDEPOTest is CDEPOTest {
    // when the CDEPO has no tokens
    //  [ ] it returns an empty array
    // when the CDEPO has one token
    //  [X] it returns the token
    // when the CDEPO has multiple tokens
    //  [X] it returns the tokens

    function test_singleToken() public {
        assertEq(CDEPO.getConvertibleDepositTokens().length, 1, "getTokens: length");
        assertEq(
            address(CDEPO.getConvertibleDepositTokens()[0]),
            address(cdToken),
            "getTokens: token"
        );
    }

    function test_multipleTokens() public {
        vm.prank(address(godmode));
        address cdTokenTwo = address(CDEPO.create(iReserveTokenTwoVault, PERIOD_MONTHS, 99e2));

        assertEq(CDEPO.getConvertibleDepositTokens().length, 2, "getTokens: length");
        assertEq(
            address(CDEPO.getConvertibleDepositTokens()[0]),
            address(cdToken),
            "getTokens: cdToken"
        );
        assertEq(
            address(CDEPO.getConvertibleDepositTokens()[1]),
            cdTokenTwo,
            "getTokens: cdTokenTwo"
        );
    }
}
