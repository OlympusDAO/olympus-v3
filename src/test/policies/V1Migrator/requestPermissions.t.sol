// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.15;

import {V1MigratorTest} from "./V1MigratorTest.sol";
import {Permissions, Keycode, toKeycode, fromKeycode} from "src/Kernel.sol";

contract V1MigratorRequestPermissionsTest is V1MigratorTest {
    // ========== REQUEST PERMISSIONS TESTS ========== //
    // Given policy is configured
    //  [X] it returns correct MINTR permissions

    function test_requestPermissions() public view {
        Permissions[] memory expectedPerms = new Permissions[](3);
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        expectedPerms[0] = Permissions({
            keycode: MINTR_KEYCODE,
            funcSelector: MINTR.mintOhm.selector
        });
        expectedPerms[1] = Permissions({
            keycode: MINTR_KEYCODE,
            funcSelector: MINTR.increaseMintApproval.selector
        });
        expectedPerms[2] = Permissions({
            keycode: MINTR_KEYCODE,
            funcSelector: MINTR.decreaseMintApproval.selector
        });

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
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
