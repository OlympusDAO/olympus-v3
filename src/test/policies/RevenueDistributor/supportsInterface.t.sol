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
    // Scenarios: RD-ERC165-P01
    function test_whenSupportedInterfaceQueried(address caller_) public {
        vm.startPrank(caller_);
        assertTrue(distributor.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(
            distributor.supportsInterface(type(IRevenueDistributor).interfaceId),
            "IRevenueDistributor"
        );
        assertTrue(
            distributor.supportsInterface(type(IRevenueDistributorRescue).interfaceId),
            "IRevenueDistributorRescue"
        );
        assertTrue(
            distributor.supportsInterface(type(IConfigOperator).interfaceId),
            "IConfigOperator"
        );
        assertTrue(distributor.supportsInterface(type(IVersioned).interfaceId), "IVersioned");
        assertTrue(distributor.supportsInterface(type(IEnabler).interfaceId), "IEnabler");
        assertTrue(distributor.supportsInterface(type(IEnablerV2).interfaceId), "IEnablerV2");
        assertTrue(distributor.supportsInterface(type(IReEnabler).interfaceId), "IReEnabler");
        assertTrue(distributor.supportsInterface(type(IGracePeriod).interfaceId), "IGracePeriod");
        vm.stopPrank();
    }

    // when any caller queries an unsupported interface
    //   [X] it returns false
    // Scenarios: RD-ERC165-P02
    function test_whenUnsupportedInterfaceQueried(address caller_) public {
        vm.prank(caller_);
        assertFalse(distributor.supportsInterface(0xffffffff), "unsupported interface");
    }

    // Scenarios: RD-ERC165-P03
    function test_whenUnrelatedInterfaceQueried_returnsFalse(bytes4 interfaceId_) public view {
        vm.assume(interfaceId_ != type(IERC165).interfaceId);
        vm.assume(interfaceId_ != type(IRevenueDistributor).interfaceId);
        vm.assume(interfaceId_ != type(IRevenueDistributorRescue).interfaceId);
        vm.assume(interfaceId_ != type(IConfigOperator).interfaceId);
        vm.assume(interfaceId_ != type(IVersioned).interfaceId);
        vm.assume(interfaceId_ != type(IEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IEnablerV2).interfaceId);
        vm.assume(interfaceId_ != type(IReEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IGracePeriod).interfaceId);

        assertFalse(
            distributor.supportsInterface(interfaceId_),
            "unrelated interface is unsupported"
        );
    }
}
