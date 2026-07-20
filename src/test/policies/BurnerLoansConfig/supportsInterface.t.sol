// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansLifecycle} from "src/policies/interfaces/IBurnerLoansLifecycle.sol";
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigSupportsInterfaceTest is BurnerLoansTest {
    function test_givenConfigDeployed_supportsInterface_advertisesOnlyConfigSurface() public view {
        assertTrue(burnerLoansConfig.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(burnerLoansConfig.supportsInterface(type(IEnabler).interfaceId), "IEnabler");
        assertTrue(burnerLoansConfig.supportsInterface(type(IEnablerV2).interfaceId), "IEnablerV2");
        assertTrue(
            burnerLoansConfig.supportsInterface(type(IGracePeriod).interfaceId),
            "IGracePeriod"
        );
        assertTrue(burnerLoansConfig.supportsInterface(type(IReEnabler).interfaceId), "IReEnabler");
        assertTrue(burnerLoansConfig.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
        assertTrue(
            burnerLoansConfig.supportsInterface(type(IBurnerLoansConfig).interfaceId),
            "IBurnerLoansConfig"
        );
        assertFalse(
            burnerLoansConfig.supportsInterface(type(IBurnerLoansLifecycle).interfaceId),
            "IBurnerLoansLifecycle"
        );
    }
}
