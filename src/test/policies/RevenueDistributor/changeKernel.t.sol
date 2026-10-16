// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel, KernelAdapter} from "src/Kernel.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorChangeKernelTest is RevenueDistributorTest {
    // Scenarios: RD-KERNEL-A01
    function test_whenNonKernelChangesKernel_reverts(address caller_, address newKernel_) public {
        vm.assume(caller_ != address(kernel));

        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        distributor.changeKernel(Kernel(newKernel_));

        assertEq(
            address(distributor.kernel()),
            address(kernel),
            "unauthorized call preserves Kernel"
        );
        assertEq(address(distributor.ROLES()), address(roles), "unauthorized call preserves ROLES");
        assertEq(distributor.treasury(), address(treasury), "unauthorized call preserves Treasury");
    }

    // Scenarios: RD-KERNEL-P01
    function test_whenKernelChangesToDistinctKernel_updatesOnlyPointer() public {
        Kernel newKernel = new Kernel();

        vm.prank(address(kernel));
        distributor.changeKernel(newKernel);

        assertEq(address(distributor.kernel()), address(newKernel), "Kernel pointer changes");
        assertEq(address(distributor.ROLES()), address(roles), "ROLES cache does not refresh");
        assertEq(distributor.treasury(), address(treasury), "Treasury cache does not refresh");
        assertFalse(distributor.isActive(), "new Kernel has not activated distributor");
    }

    // Scenarios: RD-KERNEL-P02
    function test_whenKernelChangesToSameKernel_succeedsWithoutDependencyRefresh() public {
        vm.prank(address(kernel));
        distributor.changeKernel(kernel);

        assertEq(address(distributor.kernel()), address(kernel), "same Kernel pointer remains");
        assertEq(address(distributor.ROLES()), address(roles), "ROLES cache remains");
        assertEq(distributor.treasury(), address(treasury), "Treasury cache remains");
    }

    // Scenarios: RD-KERNEL-P03
    function test_whenKernelChangesToZero_setsZeroPointer() public {
        vm.prank(address(kernel));
        distributor.changeKernel(Kernel(address(0)));

        assertEq(address(distributor.kernel()), address(0), "Kernel pointer becomes zero");
        assertEq(address(distributor.ROLES()), address(roles), "ROLES cache remains");
        assertEq(distributor.treasury(), address(treasury), "Treasury cache remains");
    }
}
