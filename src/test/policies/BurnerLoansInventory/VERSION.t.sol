// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(calls-loop)

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";
import {Kernel} from "src/Kernel.sol";

contract BurnerLoansInventoryVersionTest is BurnerLoansInventoryTest {
    // Scenarios: BLINV-VERSION-P01.
    function test_givenLifecycle_whenReadByAnyCaller(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _givenInitialLifecycle(active_, enabled_);
        bytes32 beforeState = _accountingState();
        vm.startPrank(caller_);
        (uint8 major, uint8 minor) = inventory.VERSION();
        assertEq(major, 1, "Major");
        assertEq(minor, 0, "Minor");
        vm.stopPrank();
        assertEq(_accountingState(), beforeState, "Read preserves accounting");
        vm.prank(address(kernel));
        inventory.changeKernel(Kernel(address(0)));
        vm.startPrank(caller_);
        (uint8 migratedMajor, uint8 migratedMinor) = inventory.VERSION();
        assertEq(migratedMajor, 1, "Migrated major");
        assertEq(migratedMinor, 0, "Migrated minor");
        vm.stopPrank();
    }

    // Scenarios: BLINV-VERSION-P01.
    function test_whenReadLifecycleSeeds() public {
        for (uint8 flags; flags < 4; ++flags) {
            uint256 snapshot = vm.snapshotState();
            test_givenLifecycle_whenReadByAnyCaller(outsider, flags & 1 != 0, flags & 2 != 0);
            assertTrue(vm.revertToStateAndDelete(snapshot), "Restore read lifecycle seed");
        }
    }
}

// forge-lint: disable-end(calls-loop)
