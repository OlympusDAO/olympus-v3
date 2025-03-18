// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

contract GetConvertibleTokenCDEPOTest is CDEPOTest {
    // when the input token is not supported
    //  [X] it returns the zero address
    //  [X] isSupported returns false
    // when there are multiple tokens
    //  [X] it returns the CD token
    //  [X] isSupported returns true
    // [X] it returns the CD token
    // [X] isSupported returns true

    function test_notSupported() public {
        assertEq(
            address(CDEPO.getConvertibleToken(IERC20(address(vault)))),
            address(0),
            "getToken: vault"
        );
        assertEq(CDEPO.isSupported(IERC20(address(vault))), false, "isSupported: vault");
    }

    function test_supported() public {
        assertEq(
            address(CDEPO.getConvertibleToken(iReserveToken)),
            address(cdToken),
            "getToken: iReserveToken"
        );
        assertEq(CDEPO.isSupported(iReserveToken), true, "isSupported: iReserveToken");
    }

    function test_multipleTokens() public {
        vm.prank(address(godmode));
        IConvertibleDepositERC20 cdTokenTwo = CDEPO.createToken(iReserveTokenTwoVault, 99e2);

        assertEq(
            address(CDEPO.getConvertibleToken(iReserveToken)),
            address(cdToken),
            "getToken: iReserveToken"
        );
        assertEq(CDEPO.isSupported(iReserveToken), true, "isSupported: iReserveToken");

        assertEq(
            address(CDEPO.getConvertibleToken(iReserveTokenTwo)),
            address(cdTokenTwo),
            "getToken: iReserveTokenTwo"
        );
        assertEq(CDEPO.isSupported(iReserveTokenTwo), true, "isSupported: iReserveTokenTwo");
    }
}
