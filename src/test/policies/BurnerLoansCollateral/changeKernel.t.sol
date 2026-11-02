// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansCollateralTest} from "./BurnerLoansCollateralTest.sol";
import {Kernel, KernelAdapter} from "src/Kernel.sol";

// Sequential fixture calls intentionally ignore values already checked by their helper.
// forge-lint: disable-start(unused-return,reentrancy-no-eth,calls-loop,literal-instead-of-constant)
contract BurnerLoansCollateralChangeKernelTest is BurnerLoansCollateralTest {
    // Scenarios: BLCOL-KERNEL-P01.
    function test_givenNewKernel_whenPointerChanged_thenMembershipMustBeEstablished() public {
        Kernel next = _migrateToEmptyKernel();
        assertTrue(
            kernel.isPolicyActive(_collateral),
            "Pointer change does not rewrite old Kernel membership"
        );
        assertFalse(next.isPolicyActive(_collateral), "New Kernel has not activated the action");
        assertEq(
            address(_collateral.ROLES()),
            address(roles),
            "Raw migration does not rebind cached ROLES"
        );
        _expectDepositRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_collateral)
            ),
            _borrower,
            1
        );
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-KERNEL-P01.
    function test_givenNewKernel_whenActionEnabled_thenCoreBindingMustAgree() public {
        Kernel next = _migrateToEmptyKernel();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(next),
                address(kernel)
            )
        );
        _collateral.enable("");
        _assertRejection(false, 0);
    }

    // Scenarios: BLCOL-KERNEL-P01, BLCOL-PERMISSIONS-P01, BLCOL-VERSION-P01, BLCOL-ERC165-P01.
    function test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable(
        address caller_
    ) public {
        vm.prank(address(kernel));
        _collateral.changeKernel(Kernel(address(0)));
        assertEq(address(_collateral.kernel()), address(0), "Trusted zero pointer accepted");
        vm.prank(caller_);
        assertEq(
            _collateral.requestPermissions().length,
            0,
            "Permissions do not read the missing Kernel"
        );
        vm.prank(caller_);
        (uint8 major, uint8 minor) = _collateral.VERSION();
        assertEq(major, 1, "Major version independent of Kernel");
        assertEq(minor, 0, "Minor version independent of Kernel");
        vm.prank(caller_);
        assertTrue(
            _collateral.supportsInterface(type(IBurnerLoansCollateral).interfaceId),
            "Interface view independent of Kernel"
        );
        _assertAccountingPreserved();
    }

    function _migrateToEmptyKernel() internal returns (Kernel next) {
        next = new Kernel();
        vm.prank(address(kernel));
        _collateral.changeKernel(next);
        assertEq(address(_collateral.kernel()), address(next), "Exact new Kernel pointer");
        assertEq(
            _collateral.core(),
            address(_core),
            "Immutable Core does not migrate with pointer"
        );
    }

    // Scenarios: BLCOL-KERNEL-P01.
    function test_whenKernelChanges_thenOnlyPointerChanges(
        address next_,
        bool enabled_
    ) public givenCollateralEnabled {
        _setPolicyState(_collateral, true, enabled_);
        uint48 beforeTime = _collateral.lastTransitionAt();
        vm.prank(address(_kernel));
        _collateral.changeKernel(Kernel(next_));
        assertEq(
            address(_collateral.kernel()),
            next_,
            "Kernel pointer matches input including zero/same"
        );
        assertEq(_collateral.core(), address(_core), "Immutable Core unchanged");
        assertEq(_collateral.isEnabled(), enabled_, "Local enabled flag preserved");
        assertEq(_collateral.lastTransitionAt(), beforeTime, "Transition timestamp preserved");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-KERNEL-P02.
    function test_whenNonKernelChangesKernel_reverts(
        address caller_,
        address next_
    ) public givenCollateralEnabled {
        vm.assume(caller_ != address(_kernel));
        vm.expectRevert(
            abi.encodeWithSelector(KernelAdapter.KernelAdapter_OnlyKernel.selector, caller_)
        );
        vm.prank(caller_);
        _collateral.changeKernel(Kernel(next_));
        assertEq(
            address(_collateral.kernel()),
            address(_kernel),
            "Unauthorized change preserves Kernel"
        );
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-KERNEL-P01.
    function test_whenKernelIsZeroSameOrDistinct_thenOnlyPointerChanges() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenKernelChanges_thenOnlyPointerChanges(address(0), false);
        assertTrue(vm.revertToState(checkpoint), "Restore initial Kernel");
        test_whenKernelChanges_thenOnlyPointerChanges(address(_kernel), true);
        assertTrue(vm.revertToState(checkpoint), "Restore before distinct Kernel");
        test_whenKernelChanges_thenOnlyPointerChanges(address(new Kernel()), true);
    }
}

// forge-lint: disable-end(unused-return,reentrancy-no-eth,calls-loop,literal-instead-of-constant)
