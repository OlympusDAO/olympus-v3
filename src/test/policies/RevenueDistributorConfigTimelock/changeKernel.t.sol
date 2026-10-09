// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel, KernelAdapter} from "src/Kernel.sol";
import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

contract RevenueDistributorConfigTimelockChangeKernelTest is RevenueDistributorTest {
    // Scenarios: RDCT-KERNEL-A01
    function testFuzz_whenNonKernelChangesKernel_reverts(
        address caller_,
        address newKernel_
    ) public {
        vm.assume(caller_ != address(kernel));

        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        configTimelock.changeKernel(Kernel(newKernel_));

        assertEq(address(configTimelock.kernel()), address(kernel), "Kernel remains unchanged");
        assertEq(address(configTimelock.ROLES()), address(roles), "ROLES remains unchanged");
    }

    // Scenarios: RDCT-KERNEL-P01
    function test_whenKernelChangesToDistinctKernel_updatesOnlyPointer() public {
        Kernel newKernel = new Kernel();

        vm.prank(address(kernel));
        configTimelock.changeKernel(newKernel);

        assertEq(address(configTimelock.kernel()), address(newKernel), "Kernel pointer changes");
        assertEq(address(configTimelock.ROLES()), address(roles), "ROLES cache remains unchanged");
        assertFalse(configTimelock.isActive(), "new Kernel has not activated timelock");
    }

    // Scenarios: RDCT-KERNEL-P02
    function test_whenKernelChangesToSameKernel_preservesDependencies() public {
        vm.prank(address(kernel));
        configTimelock.changeKernel(kernel);

        assertEq(
            address(configTimelock.kernel()),
            address(kernel),
            "Kernel pointer remains unchanged"
        );
        assertEq(address(configTimelock.ROLES()), address(roles), "ROLES cache remains unchanged");
    }

    // Scenarios: RDCT-KERNEL-P03
    function test_whenKernelChangesToZero_setsZeroPointer() public {
        vm.prank(address(kernel));
        configTimelock.changeKernel(Kernel(address(0)));

        assertEq(address(configTimelock.kernel()), address(0), "Kernel pointer becomes zero");
        assertEq(address(configTimelock.ROLES()), address(roles), "ROLES cache remains unchanged");
    }
}
