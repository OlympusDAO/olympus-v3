// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {Kernel, KernelAdapter} from "src/Kernel.sol";

contract BurnerLoansPayoutChangeKernelTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-KERNEL-P01, BLCU-KERNEL-P02.
    function test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges(
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        Kernel next = new Kernel();
        _assertPointerOnly(address(next), active_, enabled_);
    }

    // Scenarios: BLCU-KERNEL-P01, BLCU-KERNEL-P02.
    function test_whenKernelZero_thenInheritedInputAccepted(
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        _assertPointerOnly(address(0), active_, enabled_);
    }

    // Scenarios: BLCU-KERNEL-P03, BLCU-KERNEL-P04.
    function test_whenCallerIsNotCurrentKernel_reverts(
        address caller_,
        bool active_,
        bool enabled_,
        address next_
    ) public givenPendingBuckets {
        vm.assume(caller_ != address(_kernel));
        _setState(_payout, active_, enabled_);
        bytes32 state = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        _payout.changeKernel(Kernel(next_));
        assertEq(address(_payout.kernel()), address(_kernel), "Unauthorized pointer unchanged");
        assertEq(_ledgerDigest(), state, "Unauthorized migration preserves custody");
    }

    function _assertPointerOnly(address next_, bool active_, bool enabled_) internal {
        _setState(_payout, active_, enabled_);
        bytes32 state = _ledgerDigest();
        address roles = address(_payout.ROLES());
        uint48 last = _payout.lastTransitionAt();
        vm.recordLogs();
        vm.prank(address(_kernel));
        _payout.changeKernel(Kernel(next_));
        assertEq(vm.getRecordedLogs().length, 0, "Hook emits no event");
        assertEq(address(_payout.kernel()), next_, "Exact new pointer");
        assertEq(_payout.core(), address(_core), "Immutable Core preserved");
        assertEq(address(_payout.ROLES()), roles, "Cached roles preserved");
        assertEq(_payout.isEnabled(), enabled_, "Local flag preserved");
        assertEq(_payout.lastTransitionAt(), last, "History preserved");
        assertEq(_ledgerDigest(), state, "Migration preserves all obligations");
    }
}
