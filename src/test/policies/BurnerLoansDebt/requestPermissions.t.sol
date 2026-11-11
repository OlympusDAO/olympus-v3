// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {Permissions} from "src/Kernel.sol";
import {BurnerLoansDebtLifecycleTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtLifecycleTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(calls-loop)

contract BurnerLoansDebtRequestPermissionsTest is BurnerLoansDebtLifecycleTest {
    // Scenarios: BLDEBT-PERMISSIONS-P01.
    function test_whenPermissionsRequested_thenEmpty(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_debt, active_, enabled_);
        vm.prank(caller_);
        Permissions[] memory permissions = _debt.requestPermissions();
        assertEq(permissions.length, 0, "Action needs no module writes");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-PERMISSIONS-P01.
    function test_whenReadAcrossAllLifecycleStates_thenStable() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 checkpoint = vm.snapshotState();
                test_whenPermissionsRequested_thenEmpty(address(0xbeef), active != 0, enabled != 0);
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
