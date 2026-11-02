// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorSupportsInterfaceTest is RevenueDistributorTest {
    // when any caller queries ERC165, distribution, or rescue interface support
    //   [X] it returns true for every supported interface
    // Scenarios: RD-ERC165-P01, RD-ERC165-P04, RD-ERC165-P05, RD-ERC165-P06, RD-ERC165-P07, RD-ERC165-P08, RD-ERC165-P09, RD-ERC165-P10, RD-ERC165-P11.
    function test_whenSupportedInterfaceQueried(address caller_) public {
        vm.recordLogs();
        vm.startPrank(caller_);
        assertTrue(
            distributor.supportsInterface(type(IRevenueDistributor).interfaceId),
            "IRevenueDistributor is supported"
        );
        assertTrue(
            distributor.supportsInterface(type(IRevenueDistributorRescue).interfaceId),
            "IRevenueDistributorRescue is supported"
        );
        assertTrue(
            distributor.supportsInterface(type(IConfigOperator).interfaceId),
            "IConfigOperator is supported"
        );
        assertTrue(
            distributor.supportsInterface(type(IVersioned).interfaceId),
            "IVersioned is supported"
        );
        assertTrue(
            distributor.supportsInterface(type(IERC165).interfaceId),
            "IERC165 is supported"
        );
        assertTrue(
            distributor.supportsInterface(type(IEnabler).interfaceId),
            "IEnabler is supported"
        );
        assertTrue(
            distributor.supportsInterface(type(IEnablerV2).interfaceId),
            "IEnablerV2 is supported"
        );
        assertTrue(
            distributor.supportsInterface(type(IReEnabler).interfaceId),
            "IReEnabler is supported"
        );
        assertTrue(
            distributor.supportsInterface(type(IGracePeriod).interfaceId),
            "IGracePeriod is supported"
        );
        vm.stopPrank();
        assertEq(vm.getRecordedLogs().length, 0, "Interface read emits no logs");
    }

    // when any caller queries an unsupported interface
    //   [X] it returns false
    // Scenarios: RD-ERC165-P02.
    function test_whenUnsupportedInterfaceQueried(address caller_) public {
        vm.prank(caller_);
        assertFalse(distributor.supportsInterface(0xffffffff), "unsupported interface");
    }

    // Scenarios: RD-ERC165-P03.
    function test_whenUnrelatedInterfaceQueried_returnsFalse(
        address caller_,
        bytes4 interfaceId_
    ) public {
        vm.assume(interfaceId_ != type(IRevenueDistributor).interfaceId);
        vm.assume(interfaceId_ != type(IRevenueDistributorRescue).interfaceId);
        vm.assume(interfaceId_ != type(IConfigOperator).interfaceId);
        vm.assume(interfaceId_ != type(IVersioned).interfaceId);
        vm.assume(interfaceId_ != type(IERC165).interfaceId);
        vm.assume(interfaceId_ != type(IEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IEnablerV2).interfaceId);
        vm.assume(interfaceId_ != type(IReEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IGracePeriod).interfaceId);
        vm.prank(caller_);
        assertFalse(
            distributor.supportsInterface(interfaceId_),
            "Unknown interface is unsupported"
        );
    }
}
