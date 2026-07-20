// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {IBurnerLoansView} from "src/policies/interfaces/IBurnerLoansView.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansSupportsInterfaceTest is BurnerLoansTest {
    // supportsInterface
    // given interface ids are expected for BurnerLoans
    //  when supportsInterface is called
    //   then supported ids return true and unrelated ids return false
    function test_supportsInterface_givenSupportedInterfaces_returnsTrue() public view {
        assertTrue(burnerLoans.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(burnerLoans.supportsInterface(type(IEnabler).interfaceId), "IEnabler");
        assertTrue(burnerLoans.supportsInterface(type(IEnablerV2).interfaceId), "IEnablerV2");
        assertTrue(burnerLoans.supportsInterface(type(IGracePeriod).interfaceId), "IGracePeriod");
        assertTrue(burnerLoans.supportsInterface(type(IReEnabler).interfaceId), "IReEnabler");
        assertTrue(burnerLoans.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
        assertTrue(burnerLoans.supportsInterface(type(IOperatorAuth).interfaceId), "IOperatorAuth");
        assertTrue(
            burnerLoans.supportsInterface(type(IBurnerLoansLifecycle).interfaceId),
            "IBurnerLoansLifecycle"
        );
        assertTrue(
            burnerLoans.supportsInterface(type(IBurnerLoansView).interfaceId),
            "IBurnerLoansView"
        );
        assertFalse(
            burnerLoans.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "BurnerLoans ITimelockBatchQueue"
        );
    }
}
