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
    // Scenarios: RDTASK-ERC165-P01.
    function test_whenSupportedInterfaceQueried_returnsTrue(
        address caller_,
        uint8 interfaceIndex_,
        bool active_,
        bool enabled_
    ) public {
        bytes4[8] memory interfaceIds = [
            type(IRevenueDistributorTask).interfaceId,
            type(IPeriodicTask).interfaceId,
            type(IVersioned).interfaceId,
            type(IERC165).interfaceId,
            type(IEnabler).interfaceId,
            type(IEnablerV2).interfaceId,
            type(IReEnabler).interfaceId,
            type(IGracePeriod).interfaceId
        ];
        interfaceIndex_ = _boundUint8(interfaceIndex_, 0, 7);
        _setTaskLifecycle(active_, enabled_);

        vm.prank(caller_);
        assertTrue(task.supportsInterface(interfaceIds[interfaceIndex_]), "interface supported");
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
        bool active_,
        bool enabled_
    ) public {
        _setTaskLifecycle(active_, enabled_);
        vm.prank(caller_);
        assertFalse(task.supportsInterface(0x12345678), "unrelated interface unsupported");
    }
}
