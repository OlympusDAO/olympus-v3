// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DEPOSTest} from "./DEPOSTest.sol";

import {Module} from "src/Kernel.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

contract SetDisplayDecimalsDEPOSTest is DEPOSTest {
    // when the caller is not a permissioned address
    //  [X] it reverts
    // [X] it sets the display decimals

    function test_notPermissioned_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(this))
        );

        // Call function
        DEPOS.setDisplayDecimals(2);
    }

    function test_setDisplayDecimals() public {
        // Call function
        vm.prank(godmode);
        DEPOS.setDisplayDecimals(4);

        // Assert
        assertEq(DEPOS.displayDecimals(), 4, "displayDecimals");
    }
}
