// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

contract MonoCoolerAccessTest is MonoCoolerBaseTest {
    function expectOnlyOverseer() internal {
        vm.startPrank(OTHERS);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.stopPrank();
    }

    function expectOnlyEmergencyOrAdmin() internal {
        vm.startPrank(OTHERS);
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotAuthorised.selector));
        vm.stopPrank();
    }

    function test_access_setLtvOracle() public {
        expectOnlyOverseer();
        cooler.setLtvOracle(address(0));
    }

    function test_access_setTreasuryBorrower() public {
        expectOnlyOverseer();
        cooler.setTreasuryBorrower(address(0));
    }

    function test_access_setLiquidationsPaused() public {
        expectOnlyEmergencyOrAdmin();
        cooler.setLiquidationsPaused(true);
    }

    function test_access_setBorrowPaused() public {
        expectOnlyEmergencyOrAdmin();
        cooler.setBorrowPaused(true);
    }

    function test_access_setInterestRateWad() public {
        expectOnlyOverseer();
        cooler.setInterestRateWad(123);
    }

    function test_access_setMaxDelegateAddresses() public {
        expectOnlyOverseer();
        cooler.setMaxDelegateAddresses(ALICE, 1);
    }
}
