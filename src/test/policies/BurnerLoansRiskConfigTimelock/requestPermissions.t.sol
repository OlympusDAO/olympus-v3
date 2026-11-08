// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansRiskConfigTimelockTest} from "./BurnerLoansRiskConfigTimelockTest.sol";

contract BurnerLoansRiskConfigTimelockRequestPermissionsTest is BurnerLoansRiskConfigTimelockTest {
    // Scenarios: BLRCT-PERMISSIONS-P01.
    function test_whenPermissionsQueried(address caller_, bool active_, bool enabled_) public {
        _setState(_timelock, active_, enabled_);
        vm.prank(caller_);
        assertEq(_timelock.requestPermissions().length, 0, "no stateful module permissions");
    }
}
