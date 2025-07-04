// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IERC4626} from "src/interfaces/IERC4626.sol";

contract GetVaultSharesCDEPOTest is CDEPOTest {
    // when the vault token is not supported
    //  [X] it returns 0
    // when there are no deposits
    //  [X] it returns 0
    // [X] it returns the correct amount

    function test_notSupported() public {
        assertEq(
            CDEPO.getVaultShares(iReserveTokenTwoVault),
            0,
            "getVaultShares: iReserveTokenTwoVault"
        );
        assertEq(CDEPO.getVaultShares(IERC4626(address(cdToken))), 0, "getVaultShares: cdToken");
    }

    function test_noDeposits() public {
        assertEq(
            CDEPO.getVaultShares(iReserveTokenTwoVault),
            0,
            "getVaultShares: iReserveTokenTwoVault"
        );
    }

    function test_givenDeposits()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenRecipientHasCDToken(10e18)
    {
        assertEq(CDEPO.getVaultShares(iReserveTokenVault), 10e18, "getVaultShares: givenDeposits");
    }
}
