// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";
import {Keycode, fromKeycode, toKeycode} from "src/Kernel.sol";

contract LegacyMigratorConfigureDependenciesTest is LegacyMigratorTest {
    // ========== CONFIGURE DEPENDENCIES TESTS ========== //
    // Given policy is configured
    //  [X] it returns correct dependencies (MINTR, ROLES)

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](2);
        expectedDeps[0] = toKeycode("MINTR");
        expectedDeps[1] = toKeycode("ROLES");

        Keycode[] memory deps = migrator.configureDependencies();
        assertEq(deps.length, expectedDeps.length, "Dependencies length mismatch");
        assertEq(
            fromKeycode(deps[0]),
            fromKeycode(expectedDeps[0]),
            "First dependency should be MINTR"
        );
        assertEq(
            fromKeycode(deps[1]),
            fromKeycode(expectedDeps[1]),
            "Second dependency should be ROLES"
        );
    }
}
