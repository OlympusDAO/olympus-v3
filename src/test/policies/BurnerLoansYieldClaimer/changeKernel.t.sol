// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel, KernelAdapter} from "src/Kernel.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerChangeKernelTest is BurnerLoansYieldClaimerTest {
    // Scenarios: BLYC-KERNEL-A01.
    function test_whenCallerIsNotCurrentKernel_reverts(
        address caller_,
        address newKernel_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(caller_ != address(kernel));
        _setClaimerLifecycle(active_, enabled_);
        address rolesBefore = address(claimer.ROLES());
        uint32 executionLimitBefore = claimer.executionGasLimit();

        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        claimer.changeKernel(Kernel(newKernel_));

        assertEq(address(claimer.kernel()), address(kernel), "Kernel pointer unchanged");
        assertEq(address(claimer.ROLES()), rolesBefore, "dependency unchanged");
        assertEq(claimer.executionGasLimit(), executionLimitBefore, "configuration unchanged");
    }

    // Scenarios: BLYC-KERNEL-P01.
    function test_whenCurrentKernelChangesToDistinctKernel_updatesPointerOnly() public {
        Kernel newKernel = new Kernel();
        address rolesBefore = address(claimer.ROLES());
        uint32 executionLimitBefore = claimer.executionGasLimit();

        vm.prank(address(kernel));
        claimer.changeKernel(newKernel);

        assertEq(address(claimer.kernel()), address(newKernel), "Kernel pointer updated");
        assertFalse(claimer.isActive(), "claimer is inactive in new Kernel");
        assertEq(address(claimer.ROLES()), rolesBefore, "dependency not refreshed");
        assertEq(claimer.burnerLoans(), address(target), "Burner Loans target unchanged");
        assertEq(claimer.executionGasLimit(), executionLimitBefore, "configuration unchanged");
    }

    // Scenarios: BLYC-KERNEL-P02.
    function test_whenCurrentKernelChangesToSameKernel_succeeds() public {
        address rolesBefore = address(claimer.ROLES());

        vm.prank(address(kernel));
        claimer.changeKernel(kernel);

        assertEq(address(claimer.kernel()), address(kernel), "Kernel pointer unchanged");
        assertEq(address(claimer.ROLES()), rolesBefore, "dependency not refreshed");
        assertEq(claimer.burnerLoans(), address(target), "Burner Loans target unchanged");
    }

    // Scenarios: BLYC-KERNEL-P03.
    function test_whenCurrentKernelChangesToZero_preservesOtherState() public {
        address rolesBefore = address(claimer.ROLES());
        uint32 executionLimitBefore = claimer.executionGasLimit();

        vm.prank(address(kernel));
        claimer.changeKernel(Kernel(address(0)));

        assertEq(address(claimer.kernel()), address(0), "Kernel pointer becomes zero");
        assertEq(address(claimer.ROLES()), rolesBefore, "dependency not refreshed");
        assertEq(claimer.burnerLoans(), address(target), "Burner Loans target unchanged");
        assertEq(claimer.executionGasLimit(), executionLimitBefore, "configuration unchanged");
    }
}
