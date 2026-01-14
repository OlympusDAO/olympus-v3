// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {LegacyMigratorTest} from "./LegacyMigratorTest.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILegacyMigrator} from "src/interfaces/ILegacyMigrator.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract LegacyMigratorSupportsInterfaceTest is LegacyMigratorTest {
    // ========== SUPPORTS INTERFACE TESTS ========== //
    // Given interface check
    //  [X] it supports IERC165
    //  [X] it supports IVersioned
    //  [X] it supports ILegacyMigrator
    //  [X] it supports IEnabler
    //  [X] it does not support random interface

    function test_supportsInterface() public view {
        assertTrue(migrator.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");

        assertTrue(
            migrator.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );

        assertTrue(
            migrator.supportsInterface(type(ILegacyMigrator).interfaceId),
            "Should support ILegacyMigrator"
        );

        assertTrue(
            migrator.supportsInterface(type(IEnabler).interfaceId),
            "Should support IEnabler"
        );

        assertFalse(
            migrator.supportsInterface(bytes4(0xffffffff)),
            "Should not support random interface"
        );
    }
}
