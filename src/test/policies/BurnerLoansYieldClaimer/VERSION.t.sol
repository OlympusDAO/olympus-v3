// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerVersionTest is BurnerLoansYieldClaimerTest {
    // Scenarios: BLYC-VERSION-P01.
    function test_whenAnyCallerReadsVersion_returnsOneZero(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setClaimerLifecycle(active_, enabled_);

        vm.prank(caller_);
        (uint8 major, uint8 minor) = claimer.VERSION();

        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }
}
