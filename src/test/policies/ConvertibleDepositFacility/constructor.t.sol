// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

import {CDFacility} from "src/policies/CDFacility.sol";

contract ConvertibleDepositFacilityConstructorTest is ConvertibleDepositFacilityTest {
    // [X] it sets the contract to inactive

    function test_success() public {
        facility = new CDFacility(address(kernel), address(depositManager));

        // Assert state
        assertEq(facility.isEnabled(), false, "isEnabled");
    }
}
