// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPriceCacher} from "src/policies/interfaces/IPriceCacher.sol";

import {PriceCacherTest} from "./PriceCacherTest.sol";

contract PriceCacherSupportsInterfaceTest is PriceCacherTest {
    // given supported interfaces
    //  when the interface is queried
    //   then the query returns true
    function test_givenSupportedInterfaces_returnsTrue() public view {
        assertTrue(cacher.supportsInterface(type(IPeriodicTask).interfaceId), "IPeriodicTask");
        assertTrue(cacher.supportsInterface(type(IPriceCacher).interfaceId), "IPriceCacher");
        assertTrue(cacher.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
    }

    // given unsupported interface
    //  when the interface is queried
    //   then the query returns false
    function test_givenUnsupportedInterface_returnsFalse() public view {
        assertFalse(cacher.supportsInterface(bytes4(0xffffffff)), "unsupported interface");
    }

    // when version is queried
    //  then it returns version 1.0
    function test_VERSION() public view {
        (uint8 major, uint8 minor) = cacher.VERSION();
        assertEq(major, 1, "major");
        assertEq(minor, 0, "minor");
    }
}
