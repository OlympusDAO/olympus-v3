// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Contracts
import {PriceCacherTaskLifecycleTest} from "./fixtures/PriceCacherTaskLifecycleTest.sol";
import {Kernel, KernelAdapter} from "src/Kernel.sol";

contract PriceCacherTaskChangeKernelTest is PriceCacherTaskLifecycleTest {
    // Scenarios: PCACHER-KERNEL-A01.
    function test_whenCallerIsNotKernel_reverts(address caller_) public {
        vm.assume(caller_ != address(kernel));
        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        cacher.changeKernel(kernel);
        assertEq(address(cacher.kernel()), address(kernel), "rejection preserves Kernel");
    }

    // Scenarios: PCACHER-KERNEL-P01.
    function test_whenCurrentKernelMigrates(address reader_, bool active_, bool enabled_) public {
        _setTaskEnabled(enabled_);
        _setTaskMembership(active_);
        vm.prank(reader_);
        assertEq(
            cacher.isActive(),
            active_,
            "activity follows Kernel independently of local enablement"
        );
        Kernel replacement = new Kernel();
        address cacheBefore = cacher.priceCache();
        bytes memory pairsBefore = abi.encode(cacher.getAssetPairs());
        uint32 graceBefore = cacher.gracePeriod();
        bool enabledBefore = cacher.isEnabled();
        uint48 atBefore = cacher.lastTransitionAt();
        vm.prank(address(kernel));
        cacher.changeKernel(replacement);
        assertEq(address(cacher.kernel()), address(replacement), "new Kernel binding");
        assertEq(cacher.isEnabled(), enabledBefore, "membership migration preserves local flag");
        assertEq(cacher.lastTransitionAt(), atBefore, "migration preserves transition history");
        assertEq(cacher.priceCache(), cacheBefore, "migration preserves cache binding");
        assertEq(abi.encode(cacher.getAssetPairs()), pairsBefore, "migration preserves pair order");
        assertEq(cacher.gracePeriod(), graceBefore, "migration preserves grace");
        vm.prank(reader_);
        assertFalse(cacher.isActive(), "new Kernel has not activated policy");
    }

    // Scenarios: PCACHER-KERNEL-L01.
    function test_givenInactivePaused_whenKernelMigrates()
        public
        givenLifecycleDisabled
        givenLifecycleInactive
    {
        test_whenCurrentKernelMigrates(admin, false, false);
        assertFalse(cacher.isEnabled(), "migration preserves pause");
    }

    // Scenarios: PCACHER-KERNEL-I01.
    function test_whenKernelAssignsSameOrZeroBinding() public {
        bytes32 state = _configurationDigest();
        vm.prank(address(kernel));
        cacher.changeKernel(kernel);
        assertEq(_configurationDigest(), state, "same Kernel preserves all state");
        vm.prank(address(kernel));
        cacher.changeKernel(Kernel(address(0)));
        assertEq(address(cacher.kernel()), address(0), "inherited adapter stores supplied zero");
        assertTrue(cacher.isEnabled(), "zero binding does not alter local flag");
    }

    // Scenarios: PCACHER-KERNEL-P01.
    function test_whenMigrationLifecycleBoundarySeedsUsed() public {
        for (uint256 active; active < 2; ++active)
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 snapshot = vm.snapshotState();
                test_whenCurrentKernelMigrates(address(0), active != 0, enabled != 0);
                assertTrue(
                    vm.revertToStateAndDelete(snapshot),
                    "restore independent migration fixture"
                );
            }
    }
}
