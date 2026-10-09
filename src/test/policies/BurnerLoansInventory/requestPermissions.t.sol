// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";

contract BurnerLoansInventoryRequestPermissionsTest is BurnerLoansInventoryTest {
    // requestPermissions
    // [X] given Burner Loans Inventory, it requests only its four MINTR lifecycle permissions
    function test_requestsOnlyMintrPermissions() public view {
        Permissions[] memory permissions = inventory.requestPermissions();
        Keycode mintrKeycode = toKeycode("MINTR");
        assertEq(permissions.length, 4, "permissions length");
        for (uint256 i; i < permissions.length; ++i) {
            assertEq(
                Keycode.unwrap(permissions[i].keycode),
                Keycode.unwrap(mintrKeycode),
                "keycode"
            );
        }
        assertEq(permissions[0].funcSelector, mintr.mintOhm.selector, "mint selector");
        assertEq(permissions[1].funcSelector, mintr.burnOhm.selector, "burn selector");
        assertEq(
            permissions[2].funcSelector,
            mintr.increaseMintApproval.selector,
            "increase selector"
        );
        assertEq(
            permissions[3].funcSelector,
            mintr.decreaseMintApproval.selector,
            "decrease selector"
        );
    }
}
