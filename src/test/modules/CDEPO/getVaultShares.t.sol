// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IERC20} from "src/interfaces/IERC20.sol";

contract GetVaultSharesCDEPOTest is CDEPOTest {
    // when the token is not supported
    //  [X] it returns 0
    // when there are no deposits
    //  [X] it returns 0
    // [X] it returns the correct amount

    function test_notSupported() public {
        assertEq(CDEPO.getVaultShares(iReserveTokenTwo), 0, "getVaultShares: iReserveTokenTwo");
        assertEq(CDEPO.getVaultShares(IERC20(address(cdToken))), 0, "getVaultShares: cdToken");
    }

    function test_noDeposits() public {
        assertEq(CDEPO.getVaultShares(iReserveToken), 0, "getVaultShares: iReserveToken");
    }

    function test_givenDeposits()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenRecipientHasCDToken(10e18)
    {
        assertEq(CDEPO.getVaultShares(iReserveToken), 10e18, "getVaultShares: givenDeposits");
    }
}
