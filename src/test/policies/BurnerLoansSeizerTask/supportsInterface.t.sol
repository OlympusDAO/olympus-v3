// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";

contract BurnerLoansSeizerTaskSupportsInterfaceTest is BurnerLoansSeizerTaskTest {
    function test_supportsExpectedInterfaces() public view {
        assertTrue(_task.supportsInterface(type(IERC165).interfaceId), "ERC165 interface");
        assertTrue(
            _task.supportsInterface(type(IPeriodicTask).interfaceId),
            "periodic task interface"
        );
        assertTrue(
            _task.supportsInterface(type(IBurnerLoansSeizerTask).interfaceId),
            "_task interface"
        );
        assertTrue(_task.supportsInterface(type(IEnabler).interfaceId), "enabler interface");
        assertTrue(_task.supportsInterface(type(IEnablerV2).interfaceId), "enabler v2 interface");
        assertTrue(_task.supportsInterface(type(IReEnabler).interfaceId), "re-enabler interface");
        assertTrue(
            _task.supportsInterface(type(IGracePeriod).interfaceId),
            "grace-period interface"
        );
        assertTrue(_task.supportsInterface(type(IVersioned).interfaceId), "versioned interface");
        assertFalse(_task.supportsInterface(bytes4(0xffffffff)), "invalid interface");
    }
}
