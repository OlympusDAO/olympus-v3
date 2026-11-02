// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeize} from "src/policies/burnerloans/BurnerLoansSeize.sol";
import {Actions} from "src/Kernel.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {BurnerLoansSeizeLifecycleTest} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeLifecycleTest.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansSeizeDisableTest is BurnerLoansSeizeLifecycleTest {
    // Scenarios: BLLIQ-DISABLE-A01, BLLIQ-DISABLE-L02.
    function test_givenEnabled_whenPermittedCallerDisables_thenExactTransition(
        address caller_,
        bool emergency_,
        bool overlap_,
        bool active_
    ) public {
        _grantDisableCaller(caller_, emergency_, overlap_);
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        vm.warp(123);
        vm.expectEmit(address(_liquidation));
        emit IEnabler.Disabled();
        vm.expectEmit(address(_liquidation));
        emit IEnablerV2.Transition(caller_, false, "", 123);
        vm.prank(caller_);
        _liquidation.disable("");
        assertFalse(_liquidation.isEnabled(), "Disabled locally even when Kernel inactive");
        assertEq(_liquidation.lastTransitionAt(), 123, "Exact transition timestamp");
        assertEq(
            _kernel.isPolicyActive(_liquidation),
            active_,
            "Disable does not alter membership"
        );
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DISABLE-A03.
    function test_givenEnabled_whenUnauthorizedDisables_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        uint48 last = _liquidation.lastTransitionAt();
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _liquidation.disable("");
        assertTrue(_liquidation.isEnabled(), "Failed disable preserves enabled flag");
        assertEq(_liquidation.lastTransitionAt(), last, "Failed disable preserves timestamp");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DISABLE-L01.
    function test_givenDisabled_whenAnyCallerDisables_reverts(
        address caller_,
        bool active_
    ) public {
        _setPolicyState(_liquidation, active_, false);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _liquidation.disable("");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DISABLE-I01.
    function test_whenNonemptyDisableData_reverts(
        bytes memory data_,
        address caller_,
        bool emergency_,
        bool overlap_
    ) public {
        vm.assume(data_.length != 0);
        _grantDisableCaller(caller_, emergency_, overlap_);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(caller_);
        _liquidation.disable(data_);
        assertTrue(_liquidation.isEnabled(), "Rejected payload cannot disable");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DISABLE-A04.
    function test_givenSettlementRoleRevoked_whenDisabled_thenSucceeds() public {
        _rolesAdmin.revokeRole(_SETTLEMENT_ROLE, address(_liquidation));
        _liquidation.disable("");
        assertFalse(_liquidation.isEnabled(), "Pause independent of settlement authority");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DISABLE-D01.
    function test_givenCoreKernelViewBroken_whenDisabled_thenNoDependencyRead() public {
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _liquidation.disable("");
        assertFalse(_liquidation.isEnabled(), "Broken dependency cannot prevent pause");
        vm.clearMockedCalls();
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DISABLE-I03.
    function test_givenDisabled_whenNonemptyDisableData_thenStateWins(address caller_) public {
        _liquidation.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _liquidation.disable(hex"01");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DISABLE-I04.
    function test_givenEnabled_whenUnauthorizedNonemptyDisable_thenAuthWins(
        address caller_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && !_roles.hasRole(caller_, EMERGENCY_ROLE));
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _liquidation.disable(hex"01");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DISABLE-L03, BLLIQ-DISABLE-L04, BLLIQ-DISABLE-L05.
    function test_givenAnyCoreState_whenDisabled_thenDependenciesIgnored(
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_core, active_, enabled_);
        vm.expectEmit(address(_liquidation));
        emit IEnabler.Disabled();
        vm.expectEmit(address(_liquidation));
        emit IEnablerV2.Transition(address(this), false, "", uint48(block.timestamp));
        _liquidation.disable("");
        assertFalse(_liquidation.isEnabled(), "Core state cannot prevent pause");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DISABLE-L06.
    function test_givenNeverActivated_whenDisabled_thenInitializationPrecedence(
        address caller_
    ) public {
        BurnerLoansSeize fresh = new BurnerLoansSeize(_kernel, _core);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        fresh.disable("");
        assertFalse(fresh.isEnabled(), "Fresh action remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Rejected transition cannot initialize history");
    }

    // Scenarios: BLLIQ-DISABLE-A01, BLLIQ-DISABLE-L02.
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

    // Scenarios: BLLIQ-DISABLE-I01.
    function test_givenEmergencyOrOverlappingRoles_whenPayloadProvided_reverts() public {
        test_whenNonemptyDisableData_reverts(hex"00", address(0xabc2), true, false);
        test_whenNonemptyDisableData_reverts(hex"01", address(0xabc3), true, true);
    }

    // Scenarios: BLLIQ-DISABLE-I01.
    function test_whenPayloadLengthNonzero_reverts(uint16 length_) public {
        test_whenNonemptyDisableData_reverts(
            new bytes(bound(length_, 1, 256)),
            address(0xabc1),
            false,
            false
        );
    }

    // Scenarios: BLLIQ-DISABLE-D01.
    function test_givenCoreReportsAnotherKernel_whenDisabled_thenDependencyIgnored() public {
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        _liquidation.disable("");
        assertFalse(_liquidation.isEnabled(), "Kernel drift cannot prevent local pause");
        vm.clearMockedCalls();
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-DISABLE-I01.
    function test_whenPayloadBoundarySeedsProvided_reverts() public {
        bytes[4] memory payloads = [
            bytes(hex"00"),
            bytes(hex"01"),
            abi.encode(uint256(0)),
            new bytes(256)
        ];
        for (uint256 i; i < payloads.length; ++i) {
            uint256 checkpoint = vm.snapshotState();
            test_whenNonemptyDisableData_reverts(payloads[i], address(0xabc1), false, false);
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore enabled state and roles between payload seeds"
            );
        }
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unsafe-typecast)
