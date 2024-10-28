// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";

contract MonoCoolerAccessTest is MonoCoolerBaseTest {
    function expectOnlyOverseer() internal {
        vm.startPrank(OTHERS);
        vm.expectRevert(abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector, 
            cooler.COOLER_OVERSEER_ROLE()
        ));
        vm.stopPrank();
    }

    function test_access_setLoanToValue() public {
        expectOnlyOverseer();
        cooler.setLoanToValue(0, 0);
    }

    function test_access_setLiquidationsPaused() public {
        expectOnlyOverseer();
        cooler.setLiquidationsPaused(true);
    }

    function test_access_setBorrowPaused() public {
        expectOnlyOverseer();
        cooler.setBorrowPaused(true);
    }

    function test_access_setInterestRateBps() public {
        expectOnlyOverseer();
        cooler.setInterestRateBps(123);
    }

    function test_access_setMaxDelegateAddresses() public {
        expectOnlyOverseer();
        cooler.setMaxDelegateAddresses(ALICE, 1);
    }
}