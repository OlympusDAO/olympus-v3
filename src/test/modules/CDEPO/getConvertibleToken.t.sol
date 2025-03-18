// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {ConvertibleDepositTokenClone} from "src/modules/CDEPO/ConvertibleDepositTokenClone.sol";

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
        assertEq(CDEPO.getConvertibleToken(IERC20(address(vault))), address(0), "getToken: vault");
        assertEq(CDEPO.isSupported(IERC20(address(vault))), false, "isSupported: vault");
    }

    function test_supported() public {
        assertEq(
            CDEPO.getConvertibleToken(iReserveToken),
            address(cdToken),
            "getToken: iReserveToken"
        );
        assertEq(CDEPO.isSupported(iReserveToken), true, "isSupported: iReserveToken");
    }

    function test_multipleTokens() public {
        MockERC20 tokenTwo = new MockERC20("Token Two", "TWO", 18);
        MockERC4626 tokenTwoVault = new MockERC4626(tokenTwo, "Token Two Vault", "TWOV");

        vm.prank(address(godmode));
        ConvertibleDepositTokenClone cdTokenTwo = ConvertibleDepositTokenClone(
            CDEPO.createToken(IERC4626(address(tokenTwoVault)), 99e2)
        );

        assertEq(
            CDEPO.getConvertibleToken(iReserveToken),
            address(cdToken),
            "getToken: iReserveToken"
        );
        assertEq(CDEPO.isSupported(iReserveToken), true, "isSupported: iReserveToken");

        assertEq(
            CDEPO.getConvertibleToken(IERC20(address(tokenTwo))),
            address(cdTokenTwo),
            "getToken: tokenTwo"
        );
        assertEq(CDEPO.isSupported(IERC20(address(tokenTwo))), true, "isSupported: tokenTwo");
    }
}
