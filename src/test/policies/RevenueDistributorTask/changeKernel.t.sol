// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel, KernelAdapter} from "src/Kernel.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskChangeKernelTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-KERNEL-A01.
    function test_whenCallerIsNotCurrentKernel_reverts(
        address caller_,
        address newKernel_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(caller_ != address(kernel));
        if (!enabled_) _disableTask("");
        if (!active_) _deactivateTask();
        address rolesBefore = address(task.ROLES());

        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        task.changeKernel(Kernel(newKernel_));

        assertEq(address(task.kernel()), address(kernel), "Kernel pointer unchanged");
        assertEq(address(task.ROLES()), rolesBefore, "dependency unchanged");
    }

    // Scenarios: RDTASK-KERNEL-P01.
    function test_whenCurrentKernelChangesToDistinctKernel_updatesPointerOnly() public {
        Kernel newKernel = new Kernel();
        address rolesBefore = address(task.ROLES());

        vm.prank(address(kernel));
        task.changeKernel(newKernel);

        assertEq(address(task.kernel()), address(newKernel), "Kernel pointer updated");
        assertFalse(task.isActive(), "task is inactive in new Kernel");
        assertEq(address(task.ROLES()), rolesBefore, "dependency not refreshed");
        assertEq(task.distributor(), address(distributor), "distributor unchanged");
    }

    // Scenarios: RDTASK-KERNEL-P02.
    function test_whenCurrentKernelChangesToSameKernel_succeeds() public {
        address rolesBefore = address(task.ROLES());

        vm.prank(address(kernel));
        task.changeKernel(kernel);

        assertEq(address(task.kernel()), address(kernel), "Kernel pointer unchanged");
        assertEq(address(task.ROLES()), rolesBefore, "dependency not refreshed");
        assertEq(task.distributor(), address(distributor), "distributor unchanged");
    }

    // Scenarios: RDTASK-KERNEL-P03.
    function test_whenCurrentKernelChangesToZero_preservesOtherState() public {
        address rolesBefore = address(task.ROLES());

        vm.prank(address(kernel));
        task.changeKernel(Kernel(address(0)));

        assertEq(address(task.kernel()), address(0), "Kernel pointer becomes zero");
        assertEq(address(task.ROLES()), rolesBefore, "dependency not refreshed");
        assertEq(task.distributor(), address(distributor), "distributor unchanged");
    }
}
