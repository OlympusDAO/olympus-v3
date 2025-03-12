// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";

import {SSRLib} from "src/libraries/SSR.sol";

contract SSRTest is Test {
    function testSsrConversions() public {
        // Test cases with expected values (in basis points where 100% = 100e2)
        uint256[] memory ssrRates = new uint256[](11);

        ssrRates[0] = 1000000000418960282689704878;  //  1.33%
        ssrRates[1] = 1000000002219443553326580536;  //  7.25%
        ssrRates[2] = 1000000002659864411854984565;  //  8.75%
        ssrRates[3] = 1000000002877801985002875644;  //  9.50%
        ssrRates[4] = 1000000002950116251408586949;  //  9.75%
        ssrRates[5] = 1000000003094251918120023627;  // 10.25%
        ssrRates[6] = 1000000003166074807451009595;  // 10.50%
        ssrRates[7] = 1000000003237735385034516037;  // 10.75%
        ssrRates[8] = 1000000004154878953532704765;  // 14.00%
        ssrRates[9] = 1000000004224341833701283597;  // 14.25%
        ssrRates[10] = 1000000004362812761691191350;  // 14.75%

        uint16[] memory expectedRates = new uint16[](11);

        expectedRates[0] = 133;   //  1.33%
        expectedRates[1] = 725;   //  7.25%
        expectedRates[2] = 875;   //  8.75%
        expectedRates[3] = 950;   //  9.50%
        expectedRates[4] = 975;   //  9.75%
        expectedRates[5] = 1025;  // 10.25%
        expectedRates[6] = 1050;  // 10.50%
        expectedRates[7] = 1075;  // 10.75%
        expectedRates[8] = 1400;  // 14.00%
        expectedRates[9] = 1425;  // 14.25%
        expectedRates[10] = 1475; // 14.75%

        for (uint256 i = 0; i < ssrRates.length; i++) {
            uint16 calculatedRate = SSRLib.ssrToApr(ssrRates[i]);
            uint16 expectedRate = expectedRates[i];

            assertEq(calculatedRate, expectedRate, string.concat("SSR rate ", vm.toString(ssrRates[i])));
        }
    }
}
