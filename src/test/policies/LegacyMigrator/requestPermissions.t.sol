// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";
import {Permissions, Keycode, toKeycode, fromKeycode} from "src/Kernel.sol";

contract LegacyMigratorRequestPermissionsTest is LegacyMigratorTest {
    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](3);
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        expectedPerms[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        expectedPerms[1] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        expectedPerms[2] = Permissions(MINTR_KEYCODE, MINTR.decreaseMintApproval.selector);

        Permissions[] memory perms = migrator.requestPermissions();
        assertEq(perms.length, expectedPerms.length, "Permissions length mismatch");
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(
                fromKeycode(perms[i].keycode),
                fromKeycode(expectedPerms[i].keycode),
                "Permission keycode mismatch"
            );
            assertEq(
                perms[i].funcSelector,
                expectedPerms[i].funcSelector,
                "Permission function selector mismatch"
            );
        }
    }
}
