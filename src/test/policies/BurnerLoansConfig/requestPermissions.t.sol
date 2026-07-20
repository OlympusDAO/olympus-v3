// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigRequestPermissionsTest is BurnerLoansTest {
    function test_givenConfigPolicy_requestPermissions_returnsFloanMutators() public view {
        Permissions[] memory permissions = burnerLoansConfig.requestPermissions();

        assertEq(permissions.length, 4, "permission count");
        for (uint256 i; i < permissions.length; ++i) {
            assertEq(
                Keycode.unwrap(permissions[i].keycode),
                Keycode.unwrap(toKeycode("FLOAN")),
                "keycode"
            );
        }
        assertEq(permissions[0].funcSelector, IFLOANv1.createMarket.selector, "create market");
        assertEq(
            permissions[1].funcSelector,
            IFLOANv1.setMarketOriginationsEnabled.selector,
            "set originations"
        );
        assertEq(permissions[2].funcSelector, IFLOANv1.setMarketFacility.selector, "set facility");
        assertEq(permissions[3].funcSelector, IFLOANv1.setMarketConfig.selector, "set config");
    }
}
