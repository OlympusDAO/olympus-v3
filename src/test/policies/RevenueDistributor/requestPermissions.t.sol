// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Permissions} from "src/Kernel.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorRequestPermissionsTest is RevenueDistributorTest {
    // Scenarios: RD-PERMS-P01
    function test_whenPermissionsRequested_returnsEmptyArray(address caller_) public {
        vm.prank(caller_);
        Permissions[] memory permissions = distributor.requestPermissions();

        assertEq(permissions.length, 0, "RevenueDistributor requests no module permissions");
    }
}
