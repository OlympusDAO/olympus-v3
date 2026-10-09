// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorVersionTest is RevenueDistributorTest {
    // Scenarios: RD-VERSION-P01
    function test_whenVersionRead_returnsVersionOneZero(address caller_) public {
        vm.prank(caller_);
        (uint8 major, uint8 minor) = distributor.VERSION();

        assertEq(major, 1, "major version is one");
        assertEq(minor, 0, "minor version is zero");
    }
}
