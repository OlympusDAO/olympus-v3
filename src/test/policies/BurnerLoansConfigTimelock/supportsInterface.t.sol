// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockSupportsInterfaceTest is BurnerLoansConfigTimelockTest {
    function test_givenSupportedInterfaces_returnsTrue() public view {
        assertTrue(configTimelock.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(configTimelock.supportsInterface(type(IEnabler).interfaceId), "IEnabler");
        assertTrue(configTimelock.supportsInterface(type(IEnablerV2).interfaceId), "IEnablerV2");
        assertTrue(
            configTimelock.supportsInterface(type(IGracePeriod).interfaceId),
            "IGracePeriod"
        );
        assertTrue(configTimelock.supportsInterface(type(IReEnabler).interfaceId), "IReEnabler");
        assertTrue(configTimelock.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
        assertTrue(
            configTimelock.supportsInterface(type(IBurnerLoansConfigTimelock).interfaceId),
            "IBurnerLoansConfigTimelock"
        );
        assertTrue(
            configTimelock.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "Config ITimelockBatchQueue"
        );
        assertFalse(
            configTimelock.supportsInterface(type(IBurnerLoans).interfaceId),
            "IBurnerLoans"
        );
    }
}
