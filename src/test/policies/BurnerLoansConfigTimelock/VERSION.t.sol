// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockVERSIONTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-VERSION-P01.
    function test_givenAnyCaller_whenVersionRead_thenOneZero(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes32 beforeState = _lifecycleDigest();
        vm.prank(caller_);
        (uint8 major, uint8 minor) = _timelock.VERSION();
        assertEq(major, 1, "Major");
        assertEq(minor, 0, "Minor");
        assertEq(_lifecycleDigest(), beforeState, "Pure version has no effects");
    }
}
