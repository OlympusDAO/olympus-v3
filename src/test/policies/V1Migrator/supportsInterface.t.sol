// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {V1MigratorTest} from "./V1MigratorTest.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IV1Migrator} from "src/policies/interfaces/IV1Migrator.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract V1MigratorSupportsInterfaceTest is V1MigratorTest {
    // ========== SUPPORTS INTERFACE TESTS ========== //
    // Given interface check
    //  [X] it supports IERC165
    //  [X] it supports IVersioned
    //  [X] it supports IV1Migrator
    //  [X] it supports IEnabler
    //  [X] it does not support random interface

    function test_supportsInterface() public view {
        assertTrue(migrator.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");

        assertTrue(
            migrator.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );

        assertTrue(
            migrator.supportsInterface(type(IV1Migrator).interfaceId),
            "Should support IV1Migrator"
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
