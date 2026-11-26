// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaim.sol";
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";

contract BurnerLoansYieldClaimerTaskSupportsInterfaceTest is BurnerLoansYieldClaimerTaskTest {
    bytes4 internal constant _INVALID_INTERFACE_ID = 0xffffffff;

    // Scenarios: BLYC-ERC165-P01, BLYC-ERC165-P02, BLYC-ERC165-P03, BLYC-ERC165-P04, BLYC-ERC165-P05, BLYC-ERC165-P06, BLYC-ERC165-P07, BLYC-ERC165-P08, BLYC-ERC165-P09, BLYC-ERC165-P10.
    function test_givenSupportedInterfaces_returnsTrue(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setClaimerLifecycle(active_, enabled_);
        vm.startPrank(caller_);
        assertTrue(
            claimer.supportsInterface(type(IBurnerLoansCoreBound).interfaceId),
            "Core binding"
        );
        assertTrue(
            claimer.supportsInterface(type(IBurnerLoansYieldClaim).interfaceId),
            "Yield claim"
        );
        assertTrue(claimer.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(claimer.supportsInterface(type(IEnabler).interfaceId), "IEnabler");
        assertTrue(claimer.supportsInterface(type(IEnablerV2).interfaceId), "IEnablerV2");
        assertTrue(claimer.supportsInterface(type(IReEnabler).interfaceId), "IReEnabler");
        assertTrue(claimer.supportsInterface(type(IGracePeriod).interfaceId), "IGracePeriod");
        assertTrue(claimer.supportsInterface(type(IPeriodicTask).interfaceId), "IPeriodicTask");
        assertTrue(claimer.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
        assertTrue(
            claimer.supportsInterface(type(IBurnerLoansYieldClaimerTask).interfaceId),
            "IBurnerLoansYieldClaimerTask"
        );
    }

    // Scenarios: BLYC-ERC165-P11, BLYC-ERC165-P12.
    function test_givenUnsupportedInterface_returnsFalse() public view {
        assertFalse(claimer.supportsInterface(0x00000000), "Zero unsupported");
        assertFalse(claimer.supportsInterface(_INVALID_INTERFACE_ID), "unsupported interface");
    }

    // Scenarios: BLYC-ERC165-P13.
    function test_givenUnrelatedInterface_returnsFalse(
        bytes4 interfaceId_,
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(interfaceId_ != _INVALID_INTERFACE_ID);
        vm.assume(interfaceId_ != type(IBurnerLoansCoreBound).interfaceId);
        vm.assume(interfaceId_ != type(IBurnerLoansYieldClaim).interfaceId);
        vm.assume(interfaceId_ != type(IERC165).interfaceId);
        vm.assume(interfaceId_ != type(IEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IEnablerV2).interfaceId);
        vm.assume(interfaceId_ != type(IReEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IGracePeriod).interfaceId);
        vm.assume(interfaceId_ != type(IPeriodicTask).interfaceId);
        vm.assume(interfaceId_ != type(IVersioned).interfaceId);
        vm.assume(interfaceId_ != type(IBurnerLoansYieldClaimerTask).interfaceId);
        _setClaimerLifecycle(active_, enabled_);

        vm.prank(caller_);
        bool supported = claimer.supportsInterface(interfaceId_);

        assertFalse(supported, "unrelated interface unsupported");
    }
}
