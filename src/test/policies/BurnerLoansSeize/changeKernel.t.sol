// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Contracts
import {Kernel, KernelAdapter} from "src/Kernel.sol";
import {BurnerLoansSeizeLifecycleTest} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeLifecycleTest.sol";

// Fixture calls and ignored returns are checked through errors and ledger assertions.
// forge-lint: disable-start(unused-return)

contract BurnerLoansSeizeChangeKernelTest is BurnerLoansSeizeLifecycleTest {
    // Scenarios: BLLIQ-KERNEL-P01.
    function test_whenKernelChanges_thenOnlyPointerChanges(address next_, bool enabled_) public {
        _setPolicyState(_liquidation, true, enabled_);
        uint48 beforeTime = _liquidation.lastTransitionAt();
        vm.prank(address(_kernel));
        _liquidation.changeKernel(Kernel(next_));
        assertEq(
            address(_liquidation.kernel()),
            next_,
            "Kernel pointer matches input including zero/same"
        );
        assertEq(_liquidation.core(), address(_core), "Immutable Core unchanged");
        assertEq(_liquidation.isEnabled(), enabled_, "Local enabled flag preserved");
        assertEq(_liquidation.lastTransitionAt(), beforeTime, "Transition timestamp preserved");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-KERNEL-P02.
    function test_whenNonKernelChangesKernel_reverts(address caller_, address next_) public {
        vm.assume(caller_ != address(_kernel));
        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        _liquidation.changeKernel(Kernel(next_));
        assertEq(
            address(_liquidation.kernel()),
            address(_kernel),
            "Unauthorized change preserves Kernel"
        );
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-KERNEL-P01.
    function test_whenKernelIsZero_thenPointerChanges() public {
        test_whenKernelChanges_thenOnlyPointerChanges(address(0), true);
    }

    // Scenarios: BLLIQ-KERNEL-P01.
    function test_whenKernelIsUnchanged_thenPointerStillAccepted() public {
        test_whenKernelChanges_thenOnlyPointerChanges(address(_kernel), false);
    }

    // Scenarios: BLLIQ-KERNEL-P01.
    function test_givenMigrationToFreshKernel_whenSeized_thenAdmissionUsesNewMembership() public {
        Kernel next = new Kernel();
        address rolesBefore = address(_liquidation.ROLES());
        vm.prank(address(_kernel));
        _liquidation.changeKernel(next);
        assertFalse(_liquidation.isActive(), "New Kernel has not activated this action");
        assertTrue(
            _kernel.isPolicyActive(_liquidation),
            "Old membership is independent of pointer migration"
        );
        assertEq(address(_liquidation.ROLES()), rolesBefore, "Migration does not resolve modules");
        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_liquidation)
            )
        );
        _liquidation.seize(address(_asset), borrowers);
        _assertLoansPreserved();
    }
}

// forge-lint: disable-end(unused-return)
