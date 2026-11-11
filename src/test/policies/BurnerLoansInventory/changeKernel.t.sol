// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansInventoryTest} from "./BurnerLoansInventoryTest.sol";
import {Kernel, KernelAdapter} from "src/Kernel.sol";

contract BurnerLoansInventoryChangeKernelTest is BurnerLoansInventoryTest {
    // Scenarios: BLINV-KERNEL-P01.
    function test_whenKernelChanged(address candidate_, bool enabled_, bool active_) public {
        _givenInitialLifecycle(active_, enabled_);
        bytes32 beforeState = _accountingState();
        address rolesBefore = address(inventory.ROLES());
        vm.recordLogs();
        vm.prank(address(kernel));
        inventory.changeKernel(Kernel(candidate_));
        assertEq(vm.getRecordedLogs().length, 0, "No migration events");
        assertEq(address(inventory.kernel()), candidate_, "Exact pointer update");
        assertEq(address(inventory.ROLES()), rolesBefore, "No role rebinding");
        assertEq(inventory.isEnabled(), enabled_, "Local state unchanged");
        assertEq(inventory.core(), address(facility), "Immutable facility unchanged");
        assertEq(_accountingState(), beforeState, "No accounting or allowance changes");
    }

    // Scenarios: BLINV-KERNEL-P02.
    function test_whenUnauthorizedCaller_reverts(address caller_, address candidate_) public {
        vm.assume(caller_ != address(kernel));
        bytes32 beforeState = _accountingState();
        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        inventory.changeKernel(Kernel(candidate_));
        assertEq(address(inventory.kernel()), address(kernel), "Pointer unchanged");
        assertEq(_accountingState(), beforeState, "Accounting unchanged");
    }

    // Scenarios: BLINV-KERNEL-P01.
    function test_whenPointerBoundarySeeds() public {
        test_whenKernelChanged(address(kernel), false, true);
        test_whenKernelChanged(address(0), false, true);
    }
}
