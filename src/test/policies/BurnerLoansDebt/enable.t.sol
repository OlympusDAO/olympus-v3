// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansDebt} from "src/policies/burnerloans/BurnerLoansDebt.sol";
import {BurnerLoansDebtLifecycleTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtLifecycleTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(literal-instead-of-constant)

contract BurnerLoansDebtEnableTest is BurnerLoansDebtLifecycleTest {
    // Scenarios: BLDEBT-ENABLE-L01.
    function test_givenEnabled_whenAnyCallerEnables_reverts(address caller_, bool active_) public {
        _setPolicyState(_debt, active_, true);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _debt.enable("");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-ENABLE-L02.
    function test_givenInactive_whenEnabled_reverts() public {
        _setPolicyState(_debt, false, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_debt)
            )
        );
        _debt.enable("");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-ENABLE-A02.
    function test_givenDisabled_whenUnauthorizedEnables_reverts(address caller_) public {
        _debt.disable("");
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _debt.enable("");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-ENABLE-A01.
    function test_givenDisabled_whenAdminEnables_thenExactTransition(address caller_) public {
        vm.assume(caller_ != address(0));
        _debt.disable("");
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.warp(456);
        vm.expectEmit(address(_debt));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_debt));
        emit IEnablerV2.Transition(caller_, true, "", 456);
        vm.prank(caller_);
        _debt.enable("");
        assertTrue(_debt.isEnabled(), "Admin enables action");
        assertEq(_debt.lastTransitionAt(), 456, "Enable records timestamp");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-ENABLE-I01.
    function test_whenNonemptyEnableData_reverts(bytes memory data_) public {
        vm.assume(data_.length != 0);
        _debt.disable("");
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        _debt.enable(data_);
        assertFalse(_debt.isEnabled(), "Rejected payload cannot enable");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-ENABLE-I02.
    function test_givenEnabled_whenNonemptyEnableData_thenStateWins(address caller_) public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _debt.enable(hex"01");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-ENABLE-I03.
    function test_givenDisabled_whenUnauthorizedNonemptyEnable_thenAuthWins(
        address caller_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _debt.disable("");
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _debt.enable(hex"01");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-ENABLE-D01.
    function test_givenCoreDisabled_whenEnabled_thenRejectAndRetry() public {
        _debt.disable("");
        _core.disable("");
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_core));
        _debt.enable("");
        _assertActivationRejected(last);
        _core.enable("");
        _debt.enable("");
        _assertActivationSucceeded();
    }

    // Scenarios: BLDEBT-ENABLE-D03.
    function test_givenCoreInactiveAndDisabled_whenEnabled_thenRejectAndRetry() public {
        _debt.disable("");
        _core.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_core));
        _debt.enable("");
        _assertActivationRejected(last);
        _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        _core.enable("");
        _debt.enable("");
        _assertActivationSucceeded();
    }

    // Scenarios: BLDEBT-ENABLE-D02.
    function test_givenCoreInactive_whenEnabled_thenRejectAndRetry() public {
        _debt.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_core));
        _debt.enable("");
        _assertActivationRejected(last);
        _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        _debt.enable("");
        _assertActivationSucceeded();
    }

    // Scenarios: BLDEBT-ENABLE-D04.
    function test_givenCoreReportedKernelChanges_whenEnabled_thenKernelMismatch() public {
        _debt.disable("");
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(0x1234)
            )
        );
        _debt.enable("");
        vm.clearMockedCalls();
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-ENABLE-D06, BLDEBT-ENABLE-D08.
    function test_givenInventoryDisabled_whenEnabled_thenRejectAndRetry() public {
        _debt.disable("");
        _inventory.disable("");
        assertTrue(_core.isEnabled(), "Core remains enabled during independent Inventory drift");
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_inventory));
        _debt.enable("");
        _assertActivationRejected(last);
        _inventory.enable("");
        _debt.enable("");
        _assertActivationSucceeded();
    }

    // Scenarios: BLDEBT-ENABLE-D07, BLDEBT-ENABLE-D08.
    function test_givenInventoryInactiveAndDisabled_whenEnabled_thenRejectAndRetry() public {
        _debt.disable("");
        _inventory.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_inventory));
        assertTrue(_core.isEnabled(), "Core remains enabled during independent Inventory drift");
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_inventory));
        _debt.enable("");
        _assertActivationRejected(last);
        _kernel.executeAction(Actions.ActivatePolicy, address(_inventory));
        _inventory.enable("");
        _debt.enable("");
        _assertActivationSucceeded();
    }

    // Scenarios: BLDEBT-ENABLE-D05, BLDEBT-ENABLE-D08.
    function test_givenInventoryInactive_whenEnabled_thenRejectAndRetry() public {
        _debt.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_inventory));
        assertTrue(_core.isEnabled(), "Core remains enabled during independent Inventory drift");
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_inventory));
        _debt.enable("");
        _assertActivationRejected(last);
        _kernel.executeAction(Actions.ActivatePolicy, address(_inventory));
        _debt.enable("");
        _assertActivationSucceeded();
    }

    function test_givenInventoryKernelChanged_whenEnabled_reverts() public {
        _debt.disable("");
        Kernel other = new Kernel();
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(other))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_inventory),
                address(_kernel),
                address(other)
            )
        );
        _debt.enable("");
    }

    // Scenarios: BLDEBT-ENABLE-L03.
    function test_givenSettlementRoleRevoked_whenEnabled_reverts() public {
        _debt.disable("");
        _rolesAdmin.revokeRole(_SETTLEMENT_ROLE, address(_debt));
        uint48 last = _debt.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, _SETTLEMENT_ROLE)
        );
        _debt.enable("");
        _assertActivationRejected(last);
    }

    // Scenarios: BLDEBT-ENABLE-L04.
    function test_givenNeverActivated_whenEnabled_thenInitializationPrecedence(
        address caller_
    ) public {
        BurnerLoansDebt fresh = new BurnerLoansDebt(_kernel, _core);
        // Unset ROLES returns no ABI boolean; this dependency has no stable typed error.
        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        fresh.enable("");
        assertFalse(fresh.isEnabled(), "Fresh action remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Rejected transition cannot initialize history");
    }

    // Scenarios: BLDEBT-ENABLE-I01.
    function test_whenZeroBytePayload_reverts() public {
        test_whenNonemptyEnableData_reverts(hex"00");
    }

    // Scenarios: BLDEBT-ENABLE-I01.
    function test_whenNonzeroBytePayload_reverts() public {
        test_whenNonemptyEnableData_reverts(hex"01");
    }

    // Scenarios: BLDEBT-ENABLE-I01.
    function test_whenEncodedZeroPayload_reverts() public {
        test_whenNonemptyEnableData_reverts(abi.encode(uint256(0)));
    }

    // Scenarios: BLDEBT-ENABLE-I01.
    function test_whenMaximumPayloadPayload_reverts() public {
        test_whenNonemptyEnableData_reverts(new bytes(256));
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
