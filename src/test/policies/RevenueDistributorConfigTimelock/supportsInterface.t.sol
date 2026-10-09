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
    // Scenarios: RDCT-ERC165-P01
    function testFuzz_whenSupportedInterfaceQueried_returnsTrue(address caller_) public {
        bytes4[9] memory supported = [
            type(IRevenueDistributorConfigTimelock).interfaceId,
            type(ITimelockBatchQueue).interfaceId,
            type(IConfigTimelockBatchQueue).interfaceId,
            type(IVersioned).interfaceId,
            type(IERC165).interfaceId,
            type(IEnabler).interfaceId,
            type(IEnablerV2).interfaceId,
            type(IReEnabler).interfaceId,
            type(IGracePeriod).interfaceId
        ];

        // The fixed interface list intentionally calls the getter for each supported ID.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i; i < supported.length; ++i) {
            vm.prank(caller_);
            assertTrue(configTimelock.supportsInterface(supported[i]), "supported interface");
        }
        // forge-lint: disable-end(calls-loop)
    }

    // Scenarios: RDCT-ERC165-P02
    function testFuzz_whenInvalidInterfaceQueried_returnsFalse(address caller_) public {
        vm.prank(caller_);
        assertFalse(configTimelock.supportsInterface(0xffffffff), "invalid ERC-165 interface");
    }

    // Scenarios: RDCT-ERC165-P03
    function testFuzz_whenUnrelatedInterfaceQueried_returnsFalse(address caller_) public {
        vm.prank(caller_);
        assertFalse(
            configTimelock.supportsInterface(type(IRevenueDistributor).interfaceId),
            "unrelated interface"
        );
    }
}
