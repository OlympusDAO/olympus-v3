// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";
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
            address(CDEPO.getConvertibleDepositToken(address(vault), PERIOD_MONTHS)),
            address(0),
            "getConvertibleDepositToken: vault"
        );
        assertEq(
            address(CDEPO.getDepositToken(address(vault))),
            address(0),
            "getDepositToken: vault"
        );
        assertEq(
            CDEPO.isDepositToken(address(vault), PERIOD_MONTHS),
            false,
            "isDepositToken: vault"
        );
        assertEq(
            CDEPO.isConvertibleDepositToken(address(vault)),
            false,
            "isConvertibleDepositToken: vault"
        );
    }

    function test_supported() public {
        assertEq(
            address(CDEPO.getConvertibleDepositToken(address(iReserveToken), PERIOD_MONTHS)),
            address(cdToken),
            "getConvertibleDepositToken: iReserveToken"
        );
        assertEq(
            address(CDEPO.getDepositToken(address(cdToken))),
            address(iReserveToken),
            "getDepositToken: cdToken"
        );
        assertEq(
            CDEPO.isDepositToken(address(iReserveToken), PERIOD_MONTHS),
            true,
            "isDepositToken: iReserveToken"
        );
        assertEq(
            CDEPO.isConvertibleDepositToken(address(cdToken)),
            true,
            "isConvertibleDepositToken: cdToken"
        );
    }

    function test_multipleTokens() public {
        vm.prank(address(godmode));
        IConvertibleDepositERC20 cdTokenTwo = CDEPO.create(
            iReserveTokenTwoVault,
            PERIOD_MONTHS,
            99e2
        );

        assertEq(
            address(CDEPO.getConvertibleDepositToken(address(iReserveToken), PERIOD_MONTHS)),
            address(cdToken),
            "getConvertibleDepositToken: iReserveToken"
        );
        assertEq(
            address(CDEPO.getDepositToken(address(cdToken))),
            address(iReserveToken),
            "getDepositToken: cdToken"
        );
        assertEq(
            CDEPO.isDepositToken(address(iReserveToken), PERIOD_MONTHS),
            true,
            "isDepositToken: iReserveToken"
        );
        assertEq(
            CDEPO.isConvertibleDepositToken(address(cdToken)),
            true,
            "isConvertibleDepositToken: cdToken"
        );

        assertEq(
            address(CDEPO.getConvertibleDepositToken(address(iReserveTokenTwo), PERIOD_MONTHS)),
            address(cdTokenTwo),
            "getConvertibleDepositToken: iReserveTokenTwo"
        );
        assertEq(
            address(CDEPO.getDepositToken(address(cdTokenTwo))),
            address(iReserveTokenTwo),
            "getDepositToken: cdTokenTwo"
        );
        assertEq(
            CDEPO.isDepositToken(address(iReserveTokenTwo), PERIOD_MONTHS),
            true,
            "isDepositToken: iReserveTokenTwo"
        );
        assertEq(
            CDEPO.isConvertibleDepositToken(address(cdTokenTwo)),
            true,
            "isConvertibleDepositToken: cdTokenTwo"
        );
    }
}
