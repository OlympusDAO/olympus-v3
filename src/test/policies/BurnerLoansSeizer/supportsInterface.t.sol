// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerSupportsInterfaceTest is BurnerLoansSeizerTest {
    function test_supportsExpectedInterfaces() public view {
        assertTrue(
            seizer.supportsInterface(type(IPeriodicTask).interfaceId),
            "periodic task interface"
        );
        assertTrue(
            seizer.supportsInterface(type(IBurnerLoansSeizer).interfaceId),
            "seizer interface"
        );
        assertFalse(seizer.supportsInterface(bytes4(0xffffffff)), "invalid interface");
    }
}
