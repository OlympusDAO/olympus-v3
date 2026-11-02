// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {Kernel, KernelAdapter} from "src/Kernel.sol";

contract BurnerLoansConfigTimelockChangeKernelTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-KERNEL-P01.
    function test_givenCurrentKernel_whenPointerChangedAcrossLifecycle_thenOnlyPointerChanges(
        address next_,
        bool active_,
        bool enabled_
    ) public {
        _setState(_timelock, active_, enabled_);
        bytes32 beforeState = _lifecycleDigest();
        address roles = address(_timelock.ROLES());
        vm.prank(address(_kernel));
        _timelock.changeKernel(Kernel(next_));
        assertEq(address(_timelock.kernel()), next_, "Exact new pointer including same and zero");
        assertEq(address(_timelock.ROLES()), roles, "No dependency rebinding");
        assertEq(address(_timelock.burnerLoans()), address(_config), "Immutable Config");
        assertEq(
            _lifecycleDigest(),
            beforeState,
            "Pointer change preserves queue, lifecycle and funds"
        );
    }

    // Scenarios: BLCT-KERNEL-P02.
    function test_givenCallerNotCurrentKernel_whenPointerChanged_reverts(
        address caller_,
        address next_
    ) public {
        vm.assume(caller_ != address(_kernel));
        _transitionReverts(
            abi.encodeCall(_timelock.changeKernel, (Kernel(next_))),
            caller_,
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        assertEq(address(_timelock.kernel()), address(_kernel), "Unauthorized pointer unchanged");
    }
}
