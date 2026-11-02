// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansSeize} from "src/policies/burnerloans/BurnerLoansSeize.sol";
import {Kernel, Permissions} from "src/Kernel.sol";
import {BurnerLoansSeizeLifecycleTest} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeLifecycleTest.sol";

// Fixture casts are bounded; seed loops intentionally call external contracts.
// forge-lint: disable-start(calls-loop)

contract BurnerLoansSeizeRequestPermissionsTest is BurnerLoansSeizeLifecycleTest {
    // Scenarios: BLLIQ-PERMISSIONS-P01.
    function test_whenPermissionsRequested_thenEmpty(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_liquidation, active_, enabled_);
        vm.prank(caller_);
        Permissions[] memory permissions = _liquidation.requestPermissions();
        assertEq(permissions.length, 0, "Action needs no module writes");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-PERMISSIONS-P01.
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

    // Scenarios: BLLIQ-PERMISSIONS-P01.
    function test_givenNeverActivated_whenPermissionsRequested_thenEmpty(address caller_) public {
        _liquidation = new BurnerLoansSeize(_kernel, _core);
        vm.prank(caller_);
        assertEq(
            _liquidation.requestPermissions().length,
            0,
            "No permissions before framework setup"
        );
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-PERMISSIONS-P01.
    function test_givenKernelMigrated_whenPermissionsRequested_thenEmpty(address caller_) public {
        vm.prank(address(_kernel));
        _liquidation.changeKernel(Kernel(address(0)));
        vm.prank(caller_);
        assertEq(
            _liquidation.requestPermissions().length,
            0,
            "No dependency reads after migration"
        );
        _assertLoansPreserved();
    }
}

// forge-lint: disable-end(calls-loop)
