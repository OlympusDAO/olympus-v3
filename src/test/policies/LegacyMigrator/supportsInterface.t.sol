// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILegacyMigrator} from "src/interfaces/ILegacyMigrator.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract LegacyMigratorSupportsInterfaceTest is LegacyMigratorTest {
    function test_supportsInterface() public view {
        // Should support IERC165
        assertTrue(migrator.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");

        // Should support IVersioned
        assertTrue(
            migrator.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );

        // Should support ILegacyMigrator
        assertTrue(
            migrator.supportsInterface(type(ILegacyMigrator).interfaceId),
            "Should support ILegacyMigrator"
        );

        // Should support IEnabler (via PolicyEnabler)
        assertTrue(
            migrator.supportsInterface(type(IEnabler).interfaceId),
            "Should support IEnabler"
        );

        // Should not support random interface
        assertFalse(
            migrator.supportsInterface(bytes4(0xffffffff)),
            "Should not support random interface"
        );
    }
}
