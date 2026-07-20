// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansRequestPermissionsTest is BurnerLoansTest {
    function test_requestPermissions_requestsLifecyclePermissions() public view {
        Permissions[] memory permissions = burnerLoans.requestPermissions();

        assertEq(permissions.length, 7, "permissions length");
        assertEq(
            Keycode.unwrap(permissions[0].keycode),
            Keycode.unwrap(toKeycode("MINTR")),
            "mint keycode"
        );
        assertEq(permissions[0].funcSelector, mintr.mintOhm.selector, "mint selector");
        assertEq(permissions[1].funcSelector, mintr.burnOhm.selector, "burn selector");
        assertEq(
            Keycode.unwrap(permissions[2].keycode),
            Keycode.unwrap(toKeycode("FLOAN")),
            "FLOAN keycode"
        );
        assertEq(permissions[2].funcSelector, IFLOANv1.addCollateral.selector, "add collateral");
        assertEq(
            permissions[3].funcSelector,
            IFLOANv1.removeCollateral.selector,
            "remove collateral"
        );
        assertEq(permissions[4].funcSelector, IFLOANv1.increaseDebt.selector, "increase debt");
        assertEq(
            permissions[5].funcSelector,
            IFLOANv1.getOrCreatePosition.selector,
            "create position"
        );
        assertEq(permissions[6].funcSelector, IFLOANv1.decreaseDebt.selector, "decrease debt");
    }
}
