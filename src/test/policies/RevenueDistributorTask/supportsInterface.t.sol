// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskSupportsInterfaceTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-ERC165-P01, RDTASK-ERC165-P04, RDTASK-ERC165-P05, RDTASK-ERC165-P06, RDTASK-ERC165-P07, RDTASK-ERC165-P08, RDTASK-ERC165-P09, RDTASK-ERC165-P10.
    function test_whenSupportedInterfaceQueried_returnsTrue(address caller_) public {
        vm.recordLogs();
        vm.startPrank(caller_);
        assertTrue(
            task.supportsInterface(type(IRevenueDistributorTask).interfaceId),
            "IRevenueDistributorTask is supported"
        );
        assertTrue(
            task.supportsInterface(type(IPeriodicTask).interfaceId),
            "IPeriodicTask is supported"
        );
        assertTrue(task.supportsInterface(type(IVersioned).interfaceId), "IVersioned is supported");
        assertTrue(task.supportsInterface(type(IERC165).interfaceId), "IERC165 is supported");
        assertTrue(task.supportsInterface(type(IEnabler).interfaceId), "IEnabler is supported");
        assertTrue(task.supportsInterface(type(IEnablerV2).interfaceId), "IEnablerV2 is supported");
        assertTrue(task.supportsInterface(type(IReEnabler).interfaceId), "IReEnabler is supported");
        assertTrue(
            task.supportsInterface(type(IGracePeriod).interfaceId),
            "IGracePeriod is supported"
        );
        vm.stopPrank();
        assertEq(vm.getRecordedLogs().length, 0, "Interface read emits no logs");
    }

    // Scenarios: RDTASK-ERC165-P02.
    function test_whenInvalidInterfaceQueried_returnsFalse(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setTaskLifecycle(active_, enabled_);
        vm.prank(caller_);
        assertFalse(task.supportsInterface(0xffffffff), "invalid interface unsupported");
    }

    // Scenarios: RDTASK-ERC165-P03.
    function test_whenUnrelatedInterfaceQueried_returnsFalse(
        address caller_,
        bytes4 interfaceId_
    ) public {
        vm.assume(interfaceId_ != type(IRevenueDistributorTask).interfaceId);
        vm.assume(interfaceId_ != type(IPeriodicTask).interfaceId);
        vm.assume(interfaceId_ != type(IVersioned).interfaceId);
        vm.assume(interfaceId_ != type(IERC165).interfaceId);
        vm.assume(interfaceId_ != type(IEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IEnablerV2).interfaceId);
        vm.assume(interfaceId_ != type(IReEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IGracePeriod).interfaceId);
        vm.prank(caller_);
        assertFalse(task.supportsInterface(interfaceId_), "Unknown interface is unsupported");
    }
}
