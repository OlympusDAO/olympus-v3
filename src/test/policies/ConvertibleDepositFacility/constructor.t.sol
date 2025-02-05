// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

import {CDFacility} from "src/policies/CDFacility.sol";

contract ConstructorCDFTest is ConvertibleDepositFacilityTest {
    // [X] it sets the contract to inactive

    function test_success() public {
        facility = new CDFacility(address(kernel));

        // Assert state
        assertEq(facility.locallyActive(), false, "inactive");
    }
}
