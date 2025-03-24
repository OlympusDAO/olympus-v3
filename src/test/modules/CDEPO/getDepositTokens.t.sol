// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

contract GetDepositTokensCDEPOTest is CDEPOTest {
    // when the CDEPO has no tokens
    //  [ ] it returns an empty array
    // when the CDEPO has one token
    //  [X] it returns the token
    // when the CDEPO has multiple tokens
    //  [X] it returns the tokens

    function test_singleToken() public {
        assertEq(CDEPO.getDepositTokens().length, 1, "getTokens: length");
        assertEq(address(CDEPO.getDepositTokens()[0]), address(reserveToken), "getTokens: token");
    }

    function test_multipleTokens() public {
        vm.prank(address(godmode));
        CDEPO.create(iReserveTokenTwoVault, 99e2);

        assertEq(CDEPO.getDepositTokens().length, 2, "getTokens: length");
        assertEq(
            address(CDEPO.getDepositTokens()[0]),
            address(reserveToken),
            "getTokens: reserveToken"
        );
        assertEq(
            address(CDEPO.getDepositTokens()[1]),
            address(iReserveTokenTwo),
            "getTokens: iReserveTokenTwo"
        );
    }
}
