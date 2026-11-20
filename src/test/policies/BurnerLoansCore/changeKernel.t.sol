// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {Actions, Kernel, KernelAdapter, toKeycode} from "src/Kernel.sol";
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";

contract BurnerLoansCoreChangeKernelTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-KERNEL-D01.
    function test_givenKernelMigration_whenAuthReplaced_newKernelAdmitsGrants() public {
        bytes32 ledger = _ledger();
        uint256 epoch = _currentAuthEpoch();
        Kernel nextKernel = new Kernel();
        _kernel.executeAction(Actions.MigrateKernel, address(nextKernel));
        assertEq(address(_core.kernel()), address(nextKernel), "Core follows the actual migration");
        assertTrue(
            _kernel.isPolicyActive(_core),
            "Old registry retains membership after migration"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(nextKernel)
            )
        );
        _auth.captureAuthorization(_borrower, _borrower, 1);

        nextKernel.executeAction(Actions.InstallModule, address(_roles));
        nextKernel.executeAction(Actions.InstallModule, address(_floan));
        nextKernel.executeAction(
            Actions.InstallModule,
            address(_kernel.getModuleForKeycode(toKeycode("TRSRY")))
        );
        nextKernel.executeAction(
            Actions.InstallModule,
            address(_kernel.getModuleForKeycode(toKeycode("MINTR")))
        );
        nextKernel.executeAction(Actions.InstallModule, address(_price));
        nextKernel.executeAction(Actions.ActivatePolicy, address(_core));
        BurnerLoansAuth nextAuth = new BurnerLoansAuth(address(nextKernel), address(_core));
        _core.setAuth(address(nextAuth));
        assertEq(_currentAuthEpoch(), epoch + 1, "Replacement advances the same monotonic epoch");
        assertEq(
            _ledger(),
            ledger,
            "Migration and Auth replacement do not move custody or positions"
        );

        IBurnerLoansAuth.Permissions memory permissions;
        permissions.depositAsset = address(_asset);
        permissions.maxCollateral = type(uint128).max;
        IOperatorAuth.Grant memory grant = IOperatorAuth.Grant(
            _borrower,
            _recipient,
            0,
            0,
            type(uint48).max,
            true,
            1,
            nextAuth.authorizationContext(_borrower, _recipient),
            abi.encode(permissions)
        );
        vm.prank(_borrower);
        nextAuth.approveGrant(grant);
        bytes32 stamp = nextAuth.captureAuthorization(_borrower, _recipient, 1);
        assertEq(
            nextAuth.validate(_borrower, _recipient, 1, address(_asset), address(0), stamp),
            type(uint128).max,
            "Auth bound to the new Kernel accepts grants"
        );
        vm.prank(_borrower);
        _auth.cancelAllGrants();
        assertEq(_auth.accountEpochs(_borrower), 1, "Retired Auth cancellation remains available");
        assertEq(
            nextAuth.accountEpochs(_borrower),
            0,
            "Old cancellation leaves replacement grants live"
        );
    }

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
        _core.settleDeposit(
            IBurnerLoansCore.DepositRequest({
                asset: address(_asset),
                amount: 1,
                payer: _borrower,
                borrower: _borrower
            }),
            _borrower,
            _ownerAuthContext()
        );
    }
}
// forge-lint: disable-end(unused-return)
