// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansSeizer} from "src/policies/interfaces/IBurnerLoansSeizer.sol";

import {BurnerLoansSeizerTest} from "./BurnerLoansSeizerTest.sol";

contract BurnerLoansSeizerSupportsInterfaceTest is BurnerLoansSeizerTest {
    // supportsInterface
    // given the seizer is deployed
    //  when supportsInterface is called
    //   then it supports expected interfaces
    function test_supportsExpectedInterfaces() public view {
        assertTrue(seizer.supportsInterface(type(IERC165).interfaceId), "ERC165 interface");
        assertTrue(
            seizer.supportsInterface(type(IPeriodicTask).interfaceId),
            "periodic task interface"
        );
        assertTrue(
            seizer.supportsInterface(type(IBurnerLoansSeizer).interfaceId),
            "seizer interface"
        );
        assertTrue(seizer.supportsInterface(type(IEnabler).interfaceId), "enabler interface");
        assertTrue(seizer.supportsInterface(type(IEnablerV2).interfaceId), "enabler v2 interface");
        assertFalse(seizer.supportsInterface(bytes4(0xffffffff)), "invalid interface");
    }
}
