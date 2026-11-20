// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {PriceCacheLifecycleTest} from "./fixtures/PriceCacheLifecycleTest.sol";
import {Kernel, KernelAdapter} from "src/Kernel.sol";

contract PriceCacheChangeKernelTest is PriceCacheLifecycleTest {
    // Scenarios: PCACHE-KERNEL-A01.
    function test_whenCallerIsNotKernel_reverts(address caller_) public {
        vm.assume(caller_ != address(kernel));
        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        cache.changeKernel(kernel);
        assertEq(address(cache.kernel()), address(kernel), "rejection preserves Kernel");
    }

    // Scenarios: PCACHE-KERNEL-P01.
    function test_whenCurrentKernelMigrates() public {
        Kernel replacement = new Kernel();
        bool enabledBefore = cache.isEnabled();
        uint48 atBefore = cache.lastTransitionAt();
        vm.prank(address(kernel));
        cache.changeKernel(replacement);
        assertEq(address(cache.kernel()), address(replacement), "new Kernel binding");
        assertEq(cache.isEnabled(), enabledBefore, "membership migration preserves local flag");
        assertEq(cache.lastTransitionAt(), atBefore, "migration preserves transition history");
        assertFalse(cache.isActive(), "new Kernel has not activated policy");
    }

    // Scenarios: PCACHE-KERNEL-L01.
    function test_givenInactivePaused_whenKernelMigrates()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        Kernel replacement = new Kernel();
        vm.prank(address(kernel));
        cache.changeKernel(replacement);
        assertEq(address(cache.kernel()), address(replacement), "migration stays available");
        assertFalse(cache.isEnabled(), "pause preserved");
    }

    // Scenarios: PCACHE-KERNEL-I01.
    function test_whenKernelAssignsSameOrZeroBinding() public {
        vm.prank(address(kernel));
        cache.changeKernel(kernel);
        assertEq(address(cache.kernel()), address(kernel), "same binding retained");
        vm.prank(address(kernel));
        cache.changeKernel(Kernel(address(0)));
        assertEq(address(cache.kernel()), address(0), "inherited adapter stores supplied zero");
    }
}
