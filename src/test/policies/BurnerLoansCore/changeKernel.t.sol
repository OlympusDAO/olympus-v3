// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {Kernel, KernelAdapter} from "src/Kernel.sol";

contract BurnerLoansCoreChangeKernelTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-KERNEL-P01.
    function test_givenCurrentKernel_whenChanged(
        address next_,
        bool active_,
        bool enabled_
    ) public {
        _setCoreLifecycle(active_, enabled_);
        bytes32 ledger = _ledger();
        address roles = address(_core.ROLES());
        address floan = _core.floan();
        bool enabled = _core.isEnabled();
        vm.prank(address(_kernel));
        _core.changeKernel(Kernel(next_));
        assertEq(address(_core.kernel()), next_, "Trusted migration pointer stored including zero");
        assertEq(address(_core.ROLES()), roles, "No roles rebinding");
        assertEq(_core.floan(), floan, "No module rebinding");
        assertEq(_core.isEnabled(), enabled, "Local flag preserved");
        assertEq(_ledger(), ledger, "Migration moves no custody");
    }

    // Scenarios: BLCORE-KERNEL-P02.
    function test_givenOtherCaller_whenChanged_reverts(address caller_, address next_) public {
        vm.assume(caller_ != address(_kernel));
        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        _core.changeKernel(Kernel(next_));
        assertEq(
            address(_core.kernel()),
            address(_kernel),
            "Unauthorized migration preserves Kernel"
        );
    }

    // Scenarios: BLCORE-KERNEL-P01.
    function test_whenKernelBoundarySeeds() public {
        test_givenCurrentKernel_whenChanged(address(_kernel), true, true);
        test_givenCurrentKernel_whenChanged(address(0), true, true);
    }

    // Scenarios: BLCORE-KERNEL-P01.
    function test_givenNewKernel_whenChanged_thenMembershipIsIndependent() public {
        Kernel other = new Kernel();
        vm.prank(address(_kernel));
        _core.changeKernel(other);
        assertFalse(_core.isActive(), "New Kernel has not admitted Core");
        assertTrue(
            _kernel.isPolicyActive(_core),
            "Old Kernel membership does not establish new admission"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        vm.prank(address(_collateral));
        _core.settleDeposit(address(_asset), 1, _borrower, _borrower);
    }
}
