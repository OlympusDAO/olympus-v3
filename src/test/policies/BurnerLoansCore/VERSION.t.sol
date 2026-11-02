// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";

contract BurnerLoansCoreVersionTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-VERSION-P01.
    function test_whenVersionQueried(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 before = _state();
        vm.prank(caller_);
        (uint8 major, uint8 minor) = _core.VERSION();
        assertEq(major, 1, "Core major version");
        assertEq(minor, 0, "Core minor version");
        assertEq(_state(), before, "Version query has no effects");
    }
}
