// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansSupportsInterfaceTest is BurnerLoansTest {
    function test_supportsInterface_givenSupportedInterfaces_returnsTrue() public view {
        assertTrue(burnerLoans.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(burnerLoans.supportsInterface(type(IEnabler).interfaceId), "IEnabler");
        assertTrue(burnerLoans.supportsInterface(type(IEnablerV2).interfaceId), "IEnablerV2");
        assertTrue(burnerLoans.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
        assertTrue(burnerLoans.supportsInterface(type(IBurnerLoans).interfaceId), "IBurnerLoans");
    }

    function test_VERSION_returnsInitialVersion() public view {
        (uint8 major, uint8 minor) = burnerLoans.VERSION();

        assertEq(major, 1, "major");
        assertEq(minor, 0, "minor");
    }
}
