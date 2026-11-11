// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

contract RevenueDistributorConfigTimelockSupportsInterfaceTest is RevenueDistributorTest {
    // Scenarios: RDCT-ERC165-P01, RDCT-ERC165-P04, RDCT-ERC165-P05, RDCT-ERC165-P06, RDCT-ERC165-P07, RDCT-ERC165-P08, RDCT-ERC165-P09, RDCT-ERC165-P10, RDCT-ERC165-P11.
    function test_whenSupportedInterfaceQueried_returnsTrue(address caller_) public {
        vm.recordLogs();
        vm.startPrank(caller_);
        assertTrue(
            configTimelock.supportsInterface(type(IRevenueDistributorConfigTimelock).interfaceId),
            "IRevenueDistributorConfigTimelock is supported"
        );
        assertTrue(
            configTimelock.supportsInterface(type(ITimelockBatchQueue).interfaceId),
            "ITimelockBatchQueue is supported"
        );
        assertTrue(
            configTimelock.supportsInterface(type(IConfigTimelockBatchQueue).interfaceId),
            "IConfigTimelockBatchQueue is supported"
        );
        assertTrue(
            configTimelock.supportsInterface(type(IVersioned).interfaceId),
            "IVersioned is supported"
        );
        assertTrue(
            configTimelock.supportsInterface(type(IERC165).interfaceId),
            "IERC165 is supported"
        );
        assertTrue(
            configTimelock.supportsInterface(type(IEnabler).interfaceId),
            "IEnabler is supported"
        );
        assertTrue(
            configTimelock.supportsInterface(type(IEnablerV2).interfaceId),
            "IEnablerV2 is supported"
        );
        assertTrue(
            configTimelock.supportsInterface(type(IReEnabler).interfaceId),
            "IReEnabler is supported"
        );
        assertTrue(
            configTimelock.supportsInterface(type(IGracePeriod).interfaceId),
            "IGracePeriod is supported"
        );
        vm.stopPrank();
        assertEq(vm.getRecordedLogs().length, 0, "Interface read emits no logs");
    }

    // Scenarios: RDCT-ERC165-P02.
    function test_whenInvalidInterfaceQueried_returnsFalse(address caller_) public {
        vm.prank(caller_);
        assertFalse(configTimelock.supportsInterface(0xffffffff), "invalid ERC-165 interface");
    }

    // Scenarios: RDCT-ERC165-P03.
    function test_whenUnrelatedInterfaceQueried_returnsFalse(
        address caller_,
        bytes4 interfaceId_
    ) public {
        vm.assume(interfaceId_ != type(IRevenueDistributorConfigTimelock).interfaceId);
        vm.assume(interfaceId_ != type(ITimelockBatchQueue).interfaceId);
        vm.assume(interfaceId_ != type(IConfigTimelockBatchQueue).interfaceId);
        vm.assume(interfaceId_ != type(IVersioned).interfaceId);
        vm.assume(interfaceId_ != type(IERC165).interfaceId);
        vm.assume(interfaceId_ != type(IEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IEnablerV2).interfaceId);
        vm.assume(interfaceId_ != type(IReEnabler).interfaceId);
        vm.assume(interfaceId_ != type(IGracePeriod).interfaceId);
        vm.prank(caller_);
        assertFalse(
            configTimelock.supportsInterface(interfaceId_),
            "Unknown interface is unsupported"
        );
    }
}
