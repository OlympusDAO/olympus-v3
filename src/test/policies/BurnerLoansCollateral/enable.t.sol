// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {BL_COLLATERAL_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansCollateral} from "src/policies/burnerloans/BurnerLoansCollateral.sol";
import {BurnerLoansCollateralTest} from "src/test/policies/BurnerLoansCollateral/BurnerLoansCollateralTest.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralEnableTest is BurnerLoansCollateralTest {
    // Scenarios: BLCOL-ENABLE-L01.
    function test_givenEnabled_whenAnyCaller_reverts(
        address caller_,
        bool active_
    ) public givenCollateralEnabled {
        _setPolicyState(_collateral, active_, true);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _collateral.enable("");
        _assertLifecycle(true, START_TIMESTAMP);
    }

    // Scenarios: BLCOL-ENABLE-A02.
    function test_whenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _collateral.enable("");
        _assertLifecycle(false, 0);
    }

    // Scenarios: BLCOL-ENABLE-L02.
    function test_givenPolicyInactive_reverts() public givenCollateralInactive {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_collateral)
            )
        );
        vm.prank(admin);
        _collateral.enable("");
        _assertRejection(false, 0);
    }

    // Scenarios: BLCOL-ENABLE-D01, BLCOL-ENABLE-D02, BLCOL-ENABLE-D03.
    function test_givenCoreUnavailable_whenEnabled_thenRejectAndRetry(
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _setPolicyState(policy, active_, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(policy)
            )
        );
        vm.prank(admin);
        _collateral.enable("");
        _assertRejection(false, 0);
        _restoreCoreState(active_, enabled_);
        _expectEnabledTransition(admin);
        vm.prank(admin);
        _collateral.enable("");
        _assertLifecycle(true, START_TIMESTAMP);
    }

    // Scenarios: BLCOL-ENABLE-D04.
    function test_givenCoreKernelChanged_reverts() public {
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
        vm.prank(admin);
        _collateral.enable("");
        _assertLifecycle(false, 0);
    }

    // Scenarios: BLCOL-ENABLE-L03.
    function test_givenSettlementRoleRevoked_reverts() public {
        rolesAdmin.revokeRole(BL_COLLATERAL_POLICY_ROLE, address(_collateral));
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_COLLATERAL_POLICY_ROLE)
        );
        vm.prank(admin);
        _collateral.enable("");
        _assertLifecycle(false, 0);
    }

    // Scenarios: BLCOL-ENABLE-I01.
    function test_whenNonemptyPayload_reverts(bytes memory data_, address caller_) public {
        vm.assume(data_.length != 0);
        _grantCaller(caller_, 1, ADMIN_ROLE);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(caller_);
        _collateral.enable(data_);
        _assertLifecycle(false, 0);
    }

    // Scenarios: BLCOL-ENABLE-A01.
    function test_whenAdminCaller(address caller_) public {
        _grantCaller(caller_, 1, ADMIN_ROLE);
        vm.warp(START_TIMESTAMP + 1);
        _expectEnabledTransition(caller_);
        vm.prank(caller_);
        _collateral.enable("");
        _assertLifecycle(true, START_TIMESTAMP + 1);
    }

    // Scenarios: BLCOL-ENABLE-I01.
    function test_whenNonemptyPayloadBoundarySeedsUsed_thenExactError() public {
        bytes[4] memory data = [
            bytes(hex"00"),
            bytes(hex"01"),
            abi.encode(uint256(0)),
            new bytes(256)
        ];
        for (uint256 i; i < data.length; ++i) {
            uint256 checkpoint = vm.snapshotState();
            test_whenNonemptyPayload_reverts(data[i], address(0xC0FFEE));
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore local state between invalid payload seeds"
            );
        }
    }

    // Scenarios: BLCOL-ENABLE-L04.
    function test_givenNeverActivated_whenCalled_thenInitializationPrecedence(
        address caller_
    ) public {
        BurnerLoansCollateral fresh = new BurnerLoansCollateral(kernel, _core);
        // ROLES was never initialized. The reached call to address(0) has no ABI
        // return or product-owned error, so exact empty bytes are the available evidence.
        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        fresh.enable("");
        assertFalse(fresh.isEnabled(), "Fresh action remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Fresh history remains uninitialized");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-ENABLE-I02.
    function test_givenEnabled_whenNonemptyEnableData_thenStateWins(
        address caller_
    ) public givenCollateralEnabled {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _collateral.enable(hex"01");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-ENABLE-I03.
    function test_givenDisabled_whenUnauthorizedNonemptyEnable_thenAuthWins(
        address caller_
    ) public givenCollateralEnabled {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _collateral.disable("");
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _collateral.enable(hex"01");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-ENABLE-D01, BLCOL-ENABLE-D02, BLCOL-ENABLE-D03.
    function test_givenEachCoreLifecycleFailure_whenEnabled_thenRejectAndRetry() public {
        bool[3] memory active = [true, false, false];
        bool[3] memory enabled = [false, true, false];
        for (uint256 i; i < active.length; ++i) {
            uint256 checkpoint = vm.snapshotState();
            test_givenCoreUnavailable_whenEnabled_thenRejectAndRetry(active[i], enabled[i]);
            assertTrue(vm.revertToState(checkpoint), "Restore Core between recovery seeds");
        }
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
