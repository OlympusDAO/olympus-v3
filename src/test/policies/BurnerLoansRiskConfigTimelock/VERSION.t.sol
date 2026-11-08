// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";

contract BurnerLoansRiskConfigTimelockVersionTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-VERSION-P01.
    function test_whenVersionQueried(address caller_, bool active_, bool enabled_) public {
        _setState(_timelock, active_, enabled_);
        vm.prank(caller_);
        (uint8 major, uint8 minor) = _timelock.VERSION();
        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }
}
