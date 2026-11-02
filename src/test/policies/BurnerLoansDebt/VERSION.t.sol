// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansDebtLifecycleTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtLifecycleTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(calls-loop)

contract BurnerLoansDebtVERSIONTest is BurnerLoansDebtLifecycleTest {
    // Scenarios: BLDEBT-VERSION-P01.
    function test_whenVersionRead_thenConstant(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_debt, active_, enabled_);
        vm.prank(caller_);
        (uint8 major, uint8 minor) = _debt.VERSION();
        assertEq(major, 1, "Major version");
        assertEq(minor, 0, "Minor version");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-VERSION-P01.
    function test_whenReadAcrossAllLifecycleStates_thenStable() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 checkpoint = vm.snapshotState();
                test_whenVersionRead_thenConstant(address(0xbeef), active != 0, enabled != 0);
                assertTrue(
                    vm.revertToState(checkpoint),
                    "Restore initial state for next lifecycle seed"
                );
            }
        }
        _assertLoansPreserved();
    }
}

// forge-lint: disable-end(calls-loop)
