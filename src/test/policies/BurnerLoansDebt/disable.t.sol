// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansDebt} from "src/policies/burnerloans/BurnerLoansDebt.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {BurnerLoansDebtLifecycleTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtLifecycleTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansDebtDisableTest is BurnerLoansDebtLifecycleTest {
    // Scenarios: BLDEBT-DISABLE-A01, BLDEBT-DISABLE-L02.
    function test_givenEnabled_whenPermittedCallerDisables_thenExactTransition(
        address caller_,
        bool emergency_,
        bool overlap_,
        bool active_
    ) public {
        vm.assume(caller_ != address(0));
        _grantRoleIfMissing(emergency_ ? EMERGENCY_ROLE : ADMIN_ROLE, caller_);
        if (overlap_) _grantRoleIfMissing(emergency_ ? ADMIN_ROLE : EMERGENCY_ROLE, caller_);
        _setPolicyState(_debt, active_, true);
        vm.warp(123);
        vm.expectEmit(address(_debt));
        emit IEnabler.Disabled();
        vm.expectEmit(address(_debt));
        emit IEnablerV2.Transition(caller_, false, "", 123);
        vm.prank(caller_);
        _debt.disable("");
        assertFalse(_debt.isEnabled(), "Disabled locally even when Kernel inactive");
        assertEq(_debt.lastTransitionAt(), 123, "Exact transition timestamp");
        assertEq(_kernel.isPolicyActive(_debt), active_, "Disable does not alter membership");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-DISABLE-A03.
    function test_givenEnabled_whenUnauthorizedDisables_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        uint48 last = _debt.lastTransitionAt();
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _debt.disable("");
        assertTrue(_debt.isEnabled(), "Failed disable preserves enabled flag");
        assertEq(_debt.lastTransitionAt(), last, "Failed disable preserves timestamp");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-DISABLE-L01.
    function test_givenDisabled_whenAnyCallerDisables_reverts(
        address caller_,
        bool active_
    ) public {
        _setPolicyState(_debt, active_, false);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _debt.disable("");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-DISABLE-I01.
    function test_whenNonemptyDisableData_reverts(bytes memory data_) public {
        vm.assume(data_.length != 0);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        _debt.disable(data_);
        assertTrue(_debt.isEnabled(), "Rejected payload cannot disable");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-DISABLE-A04.
    function test_givenSettlementRoleRevoked_whenDisabled_thenSucceeds() public {
        _rolesAdmin.revokeRole(_SETTLEMENT_ROLE, address(_debt));
        _debt.disable("");
        assertFalse(_debt.isEnabled(), "Pause independent of settlement authority");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-DISABLE-D01.
    function test_givenCoreKernelViewBroken_whenDisabled_thenNoDependencyRead() public {
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _debt.disable("");
        assertFalse(_debt.isEnabled(), "Broken dependency cannot prevent pause");
        vm.clearMockedCalls();
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-DISABLE-I03.
    function test_givenDisabled_whenNonemptyDisableData_thenStateWins(address caller_) public {
        _debt.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _debt.disable(hex"01");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-DISABLE-I04.
    function test_givenEnabled_whenUnauthorizedNonemptyDisable_thenAuthWins(
        address caller_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _debt.disable(hex"01");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-DISABLE-L03, BLDEBT-DISABLE-L04, BLDEBT-DISABLE-L05.
    function test_givenAnyCoreState_whenDisabled_thenDependenciesIgnored(
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_core, active_, enabled_);
        vm.expectEmit(address(_debt));
        emit IEnabler.Disabled();
        vm.expectEmit(address(_debt));
        emit IEnablerV2.Transition(address(this), false, "", uint48(block.timestamp));
        _debt.disable("");
        assertFalse(_debt.isEnabled(), "Core state cannot prevent pause");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-DISABLE-L06.
    function test_givenNeverActivated_whenDisabled_thenInitializationPrecedence(
        address caller_
    ) public {
        BurnerLoansDebt fresh = new BurnerLoansDebt(_kernel, _core);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        fresh.disable("");
        assertFalse(fresh.isEnabled(), "Fresh action remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Rejected transition cannot initialize history");
    }

    // Scenarios: BLDEBT-DISABLE-I01.
    function test_whenZeroBytePayload_reverts() public {
        test_whenNonemptyDisableData_reverts(hex"00");
    }

    // Scenarios: BLDEBT-DISABLE-I01.
    function test_whenNonzeroBytePayload_reverts() public {
        test_whenNonemptyDisableData_reverts(hex"01");
    }

    // Scenarios: BLDEBT-DISABLE-I01.
    function test_whenEncodedZeroPayload_reverts() public {
        test_whenNonemptyDisableData_reverts(abi.encode(uint256(0)));
    }

    // Scenarios: BLDEBT-DISABLE-I01.
    function test_whenMaximumPayloadPayload_reverts() public {
        test_whenNonemptyDisableData_reverts(new bytes(256));
    }

    // Scenarios: BLDEBT-DISABLE-A01, BLDEBT-DISABLE-L02.
    function test_givenEachPermittedRole_whenDisabled_thenExactTransition() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenEnabled_whenPermittedCallerDisables_thenExactTransition(
            address(0xabc1),
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore for emergency-only caller");
        test_givenEnabled_whenPermittedCallerDisables_thenExactTransition(
            address(0xabc2),
            true,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore for overlapping caller");
        test_givenEnabled_whenPermittedCallerDisables_thenExactTransition(
            address(0xabc3),
            false,
            true,
            true
        );
    }

    // Scenarios: BLDEBT-DISABLE-A01, BLDEBT-DISABLE-L02.
    function test_givenExistingAdmin_whenDisabled_thenExactTransition() public {
        test_givenEnabled_whenPermittedCallerDisables_thenExactTransition(
            address(this),
            false,
            true,
            true
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unsafe-typecast)
