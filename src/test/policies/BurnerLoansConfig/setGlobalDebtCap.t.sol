// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigSetGlobalDebtCapTest is BurnerLoansTest {
    // [X] given admin and an enabled Config and Burner Loans Inventory
    //  when the global cap is set through Config
    //   then Config forwards the update to Burner Loans Inventory
    function test_givenAdmin_setsInventoryCap(uint128 cap_) public {
        cap_ = uint128(bound(cap_, 1, type(uint128).max));

        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.GlobalDebtCapSet(cap_);
        vm.prank(admin);
        burnerLoansConfig.setGlobalDebtCap(cap_);

        assertEq(inventory.globalDebtCapOhm(), cap_, "Burner Loans Inventory global cap");
        assertEq(
            mintr.mintApproval(address(inventory)),
            cap_,
            "Burner Loans Inventory mint approval"
        );
    }

    // [X] given a caller without the admin role
    //  when the global cap is set through Config
    //   then Config rejects the caller before forwarding
    function test_givenCallerIsNotAdmin_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        burnerLoansConfig.setGlobalDebtCap(1);
    }

    // [X] given Config is disabled
    //  when admin attempts to set the global cap
    //   then Config rejects the update
    function test_givenConfigDisabled_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(admin);
        burnerLoansConfig.setGlobalDebtCap(1);
    }
}
