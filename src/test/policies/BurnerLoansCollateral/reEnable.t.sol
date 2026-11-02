// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_COLLATERAL_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansCollateral} from "src/policies/burnerloans/BurnerLoansCollateral.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {BurnerLoansCollateralTest} from "src/test/policies/BurnerLoansCollateral/BurnerLoansCollateralTest.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralReEnableTest is BurnerLoansCollateralTest {
    // Scenarios: BLCOL-REENABLE-L02.
    function test_givenNeverEnabled_whenAnyCaller_reverts(address caller_, bool active_) public {
        if (!active_) kernel.executeAction(Actions.DeactivatePolicy, address(_collateral));
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        _collateral.reEnable();
        _assertLifecycle(false, 0);
    }

    // Scenarios: BLCOL-REENABLE-L01.
    function test_givenEnabled_whenAnyCaller_reverts(
        address caller_,
        bool active_
    ) public givenCollateralEnabled {
        _setPolicyState(_collateral, active_, true);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _collateral.reEnable();
        _assertLifecycle(true, START_TIMESTAMP);
    }

    // Scenarios: BLCOL-REENABLE-A01.
    function test_givenDisabled_whenUnauthorizedCaller_reverts(
        address caller_
    ) public givenCollateralDisabledAfterEnable {
        _assumeUnauthorized(caller_, BURNER_LOANS_ADMIN_ROLE);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _collateral.reEnable();
        _assertLifecycle(false, START_TIMESTAMP);
    }

    // Scenarios: BLCOL-REENABLE-L03.
    function test_givenDisabled_givenPolicyInactive_reverts(
        address caller_,
        uint8 roleMask_
    ) public givenCollateralDisabledAfterEnable givenCollateralInactive {
        _grantCaller(caller_, uint8(bound(roleMask_, 1, 3)), BURNER_LOANS_ADMIN_ROLE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_collateral)
            )
        );
        vm.prank(caller_);
        _collateral.reEnable();
        _assertLifecycle(false, START_TIMESTAMP);
    }

    // Scenarios: BLCOL-REENABLE-D01, BLCOL-REENABLE-D02, BLCOL-REENABLE-D03.
    function test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry(
        bool active_,
        bool enabled_,
        address caller_,
        uint8 roleMask_
    ) public givenCollateralDisabledAfterEnable {
        _grantCaller(caller_, uint8(bound(roleMask_, 1, 3)), BURNER_LOANS_ADMIN_ROLE);
        vm.assume(!active_ || !enabled_);
        _setPolicyState(policy, active_, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(policy)
            )
        );
        vm.prank(caller_);
        _collateral.reEnable();
        _assertRejection(false, START_TIMESTAMP);
        _restoreCoreState(active_, enabled_);
        _expectEnabledTransition(caller_);
        vm.prank(caller_);
        _collateral.reEnable();
        _assertLifecycle(true, START_TIMESTAMP);
    }

    // Scenarios: BLCOL-REENABLE-P03.
    function test_givenDisabled_givenGraceExpired_reverts(
        uint48 now_,
        address caller_,
        uint8 roleMask_,
        uint48 last_,
        uint32 period_
    ) public {
        _grantCaller(caller_, uint8(bound(roleMask_, 1, 3)), BURNER_LOANS_ADMIN_ROLE);
        period_ = uint32(bound(period_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, uint256(type(uint48).max) - period_ - 1));
        _prepareDisabledAt(last_, period_);
        uint48 deadline = last_ + period_;
        vm.warp(bound(now_, uint256(deadline) + 1, type(uint48).max));
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        _collateral.reEnable();
        _assertLifecycle(false, last_);
    }

    // Scenarios: BLCOL-REENABLE-D04.
    function test_givenDisabled_givenCoreKernelChanged_reverts(
        address caller_,
        uint8 roleMask_
    ) public givenCollateralDisabledAfterEnable {
        _grantCaller(caller_, uint8(bound(roleMask_, 1, 3)), BURNER_LOANS_ADMIN_ROLE);
        Kernel otherKernel = new Kernel();
        vm.prank(address(kernel));
        policy.changeKernel(otherKernel);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(policy),
                address(kernel),
                address(otherKernel)
            )
        );
        vm.prank(caller_);
        _collateral.reEnable();
        _assertLifecycle(false, START_TIMESTAMP);
    }

    // Scenarios: BLCOL-REENABLE-L04.
    function test_givenDisabled_givenSettlementRoleRevoked_reverts(
        address caller_,
        uint8 roleMask_
    ) public givenCollateralDisabledAfterEnable {
        _grantCaller(caller_, uint8(bound(roleMask_, 1, 3)), BURNER_LOANS_ADMIN_ROLE);
        rolesAdmin.revokeRole(BL_COLLATERAL_POLICY_ROLE, address(_collateral));
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_COLLATERAL_POLICY_ROLE)
        );
        vm.prank(caller_);
        _collateral.reEnable();
        _assertLifecycle(false, START_TIMESTAMP);
    }

    // Scenarios: BLCOL-REENABLE-N01.
    function test_givenDeadlineOverflow_reverts(
        uint32 period_,
        uint48 last_,
        address caller_,
        uint8 roleMask_
    ) public {
        _grantCaller(caller_, uint8(bound(roleMask_, 1, 3)), BURNER_LOANS_ADMIN_ROLE);
        uint32 period = SafeCast.toUint32(bound(period_, 1, type(uint32).max));
        uint48 last = SafeCast.toUint48(
            bound(last_, uint256(type(uint48).max) - period + 1, type(uint48).max)
        );
        _prepareDisabledAt(last, period);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                48,
                uint256(last) + period
            )
        );
        vm.prank(caller_);
        _collateral.reEnable();
        _assertLifecycle(false, last);
    }

    // Scenarios: BLCOL-REENABLE-P01.
    function test_givenDisabled_givenValidGrace_whenPermittedCaller(
        address caller_,
        uint8 roles_,
        uint48 last_,
        uint32 period_,
        uint48 now_
    ) public {
        uint32 period = SafeCast.toUint32(bound(period_, 1, type(uint32).max));
        uint48 last = SafeCast.toUint48(bound(last_, 1, uint256(type(uint48).max) - period));
        _prepareDisabledAt(last, period);
        uint48 timestamp = SafeCast.toUint48(bound(now_, last, uint256(last) + period - 1));
        _reEnableAs(caller_, SafeCast.toUint8(bound(roles_, 1, 3)), timestamp);
    }

    function test_givenDisabled_givenMaximumRepresentableDeadline() public {
        _prepareDisabledAt(type(uint48).max - type(uint32).max, type(uint32).max);
        _reEnableAs(makeAddr("adminAtMaxDeadline"), 1, type(uint48).max);
    }

    // Scenarios: BLCOL-REENABLE-P02.
    function test_givenDisabled_givenExactDeadline_whenAdminOnly()
        public
        givenCollateralDisabledAfterEnable
    {
        _reEnableAs(makeAddr("adminOnly"), 1, START_TIMESTAMP + _collateral.gracePeriod());
    }

    function test_givenDisabled_whenBurnerLoansAdminOnly()
        public
        givenCollateralDisabledAfterEnable
    {
        _reEnableAs(makeAddr("burnerLoansAdminOnly"), 2, START_TIMESTAMP);
    }

    function test_givenDisabled_whenBothRoles() public givenCollateralDisabledAfterEnable {
        _reEnableAs(makeAddr("bothRoles"), 3, START_TIMESTAMP);
    }

    function _reEnableAs(address caller_, uint8 roles_, uint48 at_) private {
        _grantCaller(caller_, roles_, BURNER_LOANS_ADMIN_ROLE);
        uint32 period = _collateral.gracePeriod();
        vm.warp(at_);
        _expectEnabledTransition(caller_);
        vm.prank(caller_);
        _collateral.reEnable();
        _assertLifecycle(true, at_);
        assertEq(_collateral.gracePeriod(), period, "Re-enablement preserves grace period");
    }

    // Scenarios: BLCOL-REENABLE-P02.
    function test_givenDisabled_whenExactFuzzedDeadline_thenAllPermittedCallers(
        uint48 last_,
        uint32 period_,
        address caller_,
        uint8 roleMask_
    ) public {
        period_ = uint32(bound(period_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, uint256(type(uint48).max) - period_));
        _prepareDisabledAt(last_, period_);
        _reEnableAs(caller_, uint8(bound(roleMask_, 1, 3)), last_ + period_);
    }

    // Scenarios: BLCOL-REENABLE-P01, BLCOL-REENABLE-P02.
    function test_givenEveryPermittedRole_whenGraceBoundarySeedsUsed_thenEnabled() public {
        for (uint8 roleMask = 1; roleMask <= 3; ++roleMask) {
            uint256 checkpoint = vm.snapshotState();
            test_givenDisabled_givenValidGrace_whenPermittedCaller(
                address(0xC0FFEE),
                roleMask,
                1,
                type(uint32).max,
                1
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore before last interior grace timestamp"
            );
            test_givenDisabled_givenValidGrace_whenPermittedCaller(
                address(0xC0FFEE),
                roleMask,
                1,
                type(uint32).max,
                type(uint32).max
            );
            assertTrue(vm.revertToState(checkpoint), "Restore before maximum exact deadline");
            test_givenDisabled_whenExactFuzzedDeadline_thenAllPermittedCallers(
                type(uint48).max - 1,
                1,
                address(0xC0FFEE),
                roleMask
            );
            assertTrue(vm.revertToState(checkpoint), "Restore before next equivalent role class");
        }
    }

    // Scenarios: BLCOL-REENABLE-P03.
    function test_givenEveryPermittedRole_whenExpiredEndpoints_thenExactDeadlineError() public {
        for (uint8 roleMask = 1; roleMask <= 3; ++roleMask) {
            uint256 checkpoint = vm.snapshotState();
            test_givenDisabled_givenGraceExpired_reverts(
                START_TIMESTAMP + 7 days + 1,
                address(0xC0FFEE),
                roleMask,
                START_TIMESTAMP,
                7 days
            );
            assertTrue(vm.revertToState(checkpoint), "Restore before maximum expired timestamp");
            test_givenDisabled_givenGraceExpired_reverts(
                type(uint48).max,
                address(0xC0FFEE),
                roleMask,
                START_TIMESTAMP,
                7 days
            );
            assertTrue(vm.revertToState(checkpoint), "Restore before next expiry caller");
        }
    }

    // Scenarios: BLCOL-REENABLE-N01.
    function test_givenEveryPermittedRole_whenDeadlineOverflowEndpoints_thenTypedError() public {
        for (uint8 roleMask = 1; roleMask <= 3; ++roleMask) {
            uint256 checkpoint = vm.snapshotState();
            test_givenDeadlineOverflow_reverts(1, type(uint48).max, address(0xC0FFEE), roleMask);
            assertTrue(vm.revertToState(checkpoint), "Restore before largest grace overflow");
            test_givenDeadlineOverflow_reverts(
                type(uint32).max,
                type(uint48).max,
                address(0xC0FFEE),
                roleMask
            );
            assertTrue(vm.revertToState(checkpoint), "Restore before next overflow caller");
        }
    }

    // Scenarios: BLCOL-REENABLE-L05.
    function test_givenNeverActivated_whenCalled_thenInitializationPrecedence(
        address caller_
    ) public {
        BurnerLoansCollateral fresh = new BurnerLoansCollateral(kernel, _core);
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
        assertFalse(fresh.isEnabled(), "Fresh action remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Fresh history remains uninitialized");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-REENABLE-A02.
    function test_givenExpiredGraceAndUnavailableCore_whenUnauthorizedReEnables_thenAuthWins(
        address caller_
    ) public givenCollateralEnabled {
        _assumeUnauthorized(caller_, BURNER_LOANS_ADMIN_ROLE);
        _collateral.disable("");
        _core.disable("");
        vm.warp(uint256(_collateral.lastTransitionAt()) + _collateral.gracePeriod() + 1);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _collateral.reEnable();
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-REENABLE-D01, BLCOL-REENABLE-D02, BLCOL-REENABLE-D03.
    function test_givenEachCoreLifecycleFailure_whenReEnabled_thenRejectAndRetry() public {
        bool[3] memory active = [true, false, false];
        bool[3] memory enabled = [false, true, false];
        for (uint256 i; i < active.length; ++i) {
            uint256 checkpoint = vm.snapshotState();
            test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry(
                active[i],
                enabled[i],
                admin,
                1
            );
            assertTrue(vm.revertToState(checkpoint), "Restore Core between recovery seeds");
        }
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
