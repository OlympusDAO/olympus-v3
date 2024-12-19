// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDPOSTest} from "./CDPOSTest.sol";

import {Module} from "src/Kernel.sol";

contract SetDisplayDecimalsCDPOSTest is CDPOSTest {
    // when the caller is not a permissioned address
    //  [ ] it reverts
    // [ ] it sets the display decimals

    function test_notPermissioned_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );

        // Call function
        CDPOS.setDisplayDecimals(2);
    }

    function test_setDisplayDecimals() public {
        // Call function
        vm.prank(godmode);
        CDPOS.setDisplayDecimals(4);

        // Assert
        assertEq(CDPOS.displayDecimals(), 4, "displayDecimals");
    }
}
