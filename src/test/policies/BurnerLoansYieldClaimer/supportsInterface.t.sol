// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerSupportsInterfaceTest is BurnerLoansYieldClaimerTest {
    function test_givenSupportedInterfaces_returnsTrue() public view {
        assertTrue(claimer.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(claimer.supportsInterface(type(IEnabler).interfaceId), "IEnabler");
        assertTrue(claimer.supportsInterface(type(IEnablerV2).interfaceId), "IEnablerV2");
        assertTrue(claimer.supportsInterface(type(IReEnabler).interfaceId), "IReEnabler");
        assertTrue(claimer.supportsInterface(type(IGracePeriod).interfaceId), "IGracePeriod");
        assertTrue(claimer.supportsInterface(type(IPeriodicTask).interfaceId), "IPeriodicTask");
        assertTrue(claimer.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
        assertTrue(
            claimer.supportsInterface(type(IBurnerLoansYieldClaimer).interfaceId),
            "IBurnerLoansYieldClaimer"
        );
    }

    function test_givenUnsupportedInterface_returnsFalse() public view {
        assertFalse(claimer.supportsInterface(bytes4(0xffffffff)), "unsupported interface");
    }
}
