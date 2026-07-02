// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Keycode, Permissions, toKeycode} from "src/Kernel.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansConfigureDependenciesTest is BurnerLoansTest {
    function test_configureDependencies_setsModules() public view {
        assertEq(address(burnerLoans.MINTR()), address(mintr), "MINTR");
        assertEq(address(burnerLoans.PRICE()), address(price), "PRICE");
        assertEq(address(burnerLoans.ROLES()), address(roles), "ROLES");
        assertEq(address(burnerLoans.TRSRY()), address(trsry), "TRSRY");
    }

    function test_requestPermissions_requestsMinterPermissions() public view {
        Permissions[] memory permissions = burnerLoans.requestPermissions();

        assertEq(permissions.length, 2, "permissions length");
        assertEq(
            Keycode.unwrap(permissions[0].keycode),
            Keycode.unwrap(toKeycode("MINTR")),
            "mint keycode"
        );
        assertEq(permissions[0].funcSelector, mintr.mintOhm.selector, "mint selector");
        assertEq(
            Keycode.unwrap(permissions[1].keycode),
            Keycode.unwrap(toKeycode("MINTR")),
            "burn keycode"
        );
        assertEq(permissions[1].funcSelector, mintr.burnOhm.selector, "burn selector");
    }
}
