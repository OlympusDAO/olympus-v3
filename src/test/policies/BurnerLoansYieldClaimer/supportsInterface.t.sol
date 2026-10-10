// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansYieldClaimer} from "src/policies/interfaces/IBurnerLoansYieldClaimer.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerSupportsInterfaceTest is BurnerLoansYieldClaimerTest {
    bytes4 internal constant _INVALID_INTERFACE_ID = 0xffffffff;

    // Scenarios: BLYC-ERC165-P01.
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

    // Scenarios: BLYC-ERC165-P02.
    function test_givenUnsupportedInterface_returnsFalse() public view {
        assertFalse(claimer.supportsInterface(_INVALID_INTERFACE_ID), "unsupported interface");
    }

    // Scenarios: BLYC-ERC165-P03.
    function test_givenUnrelatedInterface_returnsFalse(
        bytes4 interfaceId_,
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(interfaceId_ != _INVALID_INTERFACE_ID);
        vm.assume(interfaceId_ != type(IERC165).interfaceId);
        vm.assume(interfaceId_ != type(IEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IEnablerV2).interfaceId);
        vm.assume(interfaceId_ != type(IReEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IGracePeriod).interfaceId);
        vm.assume(interfaceId_ != type(IPeriodicTask).interfaceId);
        vm.assume(interfaceId_ != type(IVersioned).interfaceId);
        vm.assume(interfaceId_ != type(IBurnerLoansYieldClaimer).interfaceId);
        _setClaimerLifecycle(active_, enabled_);

        vm.prank(caller_);
        bool supported = claimer.supportsInterface(interfaceId_);

        assertFalse(supported, "unrelated interface unsupported");
    }
}
