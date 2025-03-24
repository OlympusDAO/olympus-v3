// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IERC4626} from "src/interfaces/IERC4626.sol";

contract GetDebtCDEPOTest is CDEPOTest {
    // given the vault token is not supported
    //  [X] it returns 0
    // [X] it returns the debt

    function test_notSupported() public {
        assertEq(CDEPO.getDebt(IERC4626(address(cdToken)), recipient), 0, "not supported");
    }

    function test_supported()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
    {
        // Incur debt
        vm.prank(godmode);
        CDEPO.incurDebt(iReserveTokenVault, 10e18);

        // Assert debt
        assertEq(CDEPO.getDebt(iReserveTokenVault, godmode), 10e18, "supported");
    }
}
