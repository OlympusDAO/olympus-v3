// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {Kernel, KernelAdapter} from "src/Kernel.sol";
import {BurnerLoansDebtLifecycleTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtLifecycleTest.sol";

contract BurnerLoansDebtChangeKernelTest is BurnerLoansDebtLifecycleTest {
    // Scenarios: BLDEBT-KERNEL-P01.
    function test_whenKernelChanges_thenOnlyPointerChanges(address next_, bool enabled_) public {
        _setPolicyState(_debt, true, enabled_);
        uint48 beforeTime = _debt.lastTransitionAt();
        vm.prank(address(_kernel));
        _debt.changeKernel(Kernel(next_));
        assertEq(
            address(_debt.kernel()),
            next_,
            "Kernel pointer matches input including zero/same"
        );
        assertEq(_debt.core(), address(_core), "Immutable Core unchanged");
        assertEq(_debt.isEnabled(), enabled_, "Local enabled flag preserved");
        assertEq(_debt.lastTransitionAt(), beforeTime, "Transition timestamp preserved");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-KERNEL-P02.
    function test_whenNonKernelChangesKernel_reverts(address caller_, address next_) public {
        vm.assume(caller_ != address(_kernel));
        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        _debt.changeKernel(Kernel(next_));
        assertEq(address(_debt.kernel()), address(_kernel), "Unauthorized change preserves Kernel");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-KERNEL-P01.
    function test_whenKernelIsZero_thenPointerChanges() public {
        test_whenKernelChanges_thenOnlyPointerChanges(address(0), true);
    }

    // Scenarios: BLDEBT-KERNEL-P01.
    function test_whenKernelIsUnchanged_thenPointerStillAccepted() public {
        test_whenKernelChanges_thenOnlyPointerChanges(address(_kernel), false);
    }
}
