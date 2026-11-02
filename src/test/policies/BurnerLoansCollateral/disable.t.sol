// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {BL_COLLATERAL_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCollateral} from "src/policies/burnerloans/BurnerLoansCollateral.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {BurnerLoansCollateralTest} from "src/test/policies/BurnerLoansCollateral/BurnerLoansCollateralTest.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralDisableTest is BurnerLoansCollateralTest {
    // Scenarios: BLCOL-DISABLE-L01.
    function test_givenDisabled_whenAnyCaller_reverts(address caller_) public {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _collateral.disable("");
        _assertLifecycle(false, 0);
    }

    // Scenarios: BLCOL-DISABLE-A03.
    function test_givenEnabled_whenUnauthorizedCaller_reverts(
        address caller_
    ) public givenCollateralEnabled {
        _assumeUnauthorized(caller_, EMERGENCY_ROLE);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _collateral.disable("");
        _assertLifecycle(true, START_TIMESTAMP);
    }

    // Scenarios: BLCOL-DISABLE-I01.
    function test_givenEnabled_whenNonemptyPayload_reverts(
        bytes memory data_,
        address caller_,
        uint8 roleMask_
    ) public givenCollateralEnabled {
        vm.assume(data_.length != 0);
        _grantCaller(caller_, uint8(bound(roleMask_, 1, 3)), EMERGENCY_ROLE);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(caller_);
        _collateral.disable(data_);
        _assertLifecycle(true, START_TIMESTAMP);
    }

    // Scenarios: BLCOL-DISABLE-L02.
    function test_givenEnabled_givenPolicyInactive()
        public
        givenCollateralEnabled
        givenCollateralInactive
    {
        vm.prank(admin);
        _collateral.disable("");
        _assertLifecycle(false, START_TIMESTAMP);
        assertFalse(kernel.isPolicyActive(_collateral), "Disable must not reactivate policy");
    }

    // Scenarios: BLCOL-DISABLE-L03, BLCOL-DISABLE-L04, BLCOL-DISABLE-L05.
    function test_givenEnabled_givenCoreUnavailable(
        bool active_,
        bool enabled_
    ) public givenCollateralEnabled {
        vm.assume(!active_ || !enabled_);
        _setPolicyState(policy, active_, enabled_);
        vm.prank(emergency);
        _collateral.disable("");
        _assertRejection(false, START_TIMESTAMP);
        assertEq(policy.isEnabled(), enabled_, "Disable must preserve Core local state");
        assertEq(kernel.isPolicyActive(policy), active_, "Disable must preserve Core membership");
    }

    // Scenarios: BLCOL-DISABLE-A01, BLCOL-DISABLE-L02.
    function test_givenEnabled_whenPermittedCaller(
        address caller_,
        uint8 roles_,
        bool active_
    ) public givenCollateralEnabled {
        _setPolicyState(_collateral, active_, true);
        _disableAs(caller_, SafeCast.toUint8(bound(roles_, 1, 3)));
        assertEq(kernel.isPolicyActive(_collateral), active_, "Disable preserves membership");
    }

    // Scenarios: BLCOL-DISABLE-A01.
    function test_givenEnabled_whenAdminOnly() public givenCollateralEnabled {
        _disableAs(makeAddr("adminOnly"), 1);
    }

    // Scenarios: BLCOL-DISABLE-A01.
    function test_givenEnabled_whenEmergencyOnly() public givenCollateralEnabled {
        _disableAs(makeAddr("emergencyOnly"), 2);
    }

    // Scenarios: BLCOL-DISABLE-A01.
    function test_givenEnabled_whenBothRoles() public givenCollateralEnabled {
        _disableAs(makeAddr("bothRoles"), 3);
    }

    function _disableAs(address caller_, uint8 roles_) private {
        _grantCaller(caller_, roles_, EMERGENCY_ROLE);
        vm.warp(START_TIMESTAMP + 1);
        vm.expectEmit(address(_collateral));
        emit Disabled();
        vm.expectEmit(address(_collateral));
        emit Transition(caller_, false, "", START_TIMESTAMP + 1);
        vm.prank(caller_);
        _collateral.disable("");
        _assertLifecycle(false, START_TIMESTAMP + 1);
    }

    // Scenarios: BLCOL-DISABLE-I01.
    function test_whenNonemptyPayloadBoundarySeedsUsed_thenExactError() public {
        bytes[4] memory data = [
            bytes(hex"00"),
            bytes(hex"01"),
            abi.encode(uint256(0)),
            new bytes(256)
        ];
        for (uint256 i; i < data.length; ++i) {
            uint256 checkpoint = vm.snapshotState();
            test_givenEnabled_whenNonemptyPayload_reverts(data[i], address(0xC0FFEE), 1);
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore local state between invalid payload seeds"
            );
        }
    }

    // Scenarios: BLCOL-DISABLE-L06.
    function test_givenNeverActivated_whenCalled_thenInitializationPrecedence(
        address caller_
    ) public {
        BurnerLoansCollateral fresh = new BurnerLoansCollateral(kernel, _core);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        fresh.disable("");
        assertFalse(fresh.isEnabled(), "Fresh action remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Fresh history remains uninitialized");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-DISABLE-L01.
    function test_givenDisabled_whenAnyCallerDisables_reverts(
        address caller_,
        bool active_
    ) public givenCollateralEnabled {
        _setPolicyState(_collateral, active_, false);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _collateral.disable("");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-DISABLE-A04.
    function test_givenSettlementRoleRevoked_whenDisabled_thenSucceeds()
        public
        givenCollateralEnabled
    {
        _rolesAdmin.revokeRole(BL_COLLATERAL_POLICY_ROLE, address(_collateral));
        _collateral.disable("");
        assertFalse(_collateral.isEnabled(), "Pause independent of settlement authority");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-DISABLE-D01.
    function test_givenCoreKernelViewBroken_whenDisabled_thenNoDependencyRead()
        public
        givenCollateralEnabled
    {
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _collateral.disable("");
        assertFalse(_collateral.isEnabled(), "Broken dependency cannot prevent pause");
        vm.clearMockedCalls();
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-DISABLE-I03.
    function test_givenDisabled_whenNonemptyDisableData_thenStateWins(
        address caller_
    ) public givenCollateralEnabled {
        _collateral.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _collateral.disable(hex"01");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-DISABLE-I04.
    function test_givenEnabled_whenUnauthorizedNonemptyDisable_thenAuthWins(
        address caller_
    ) public givenCollateralEnabled {
        _assumeUnauthorized(caller_, EMERGENCY_ROLE);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _collateral.disable(hex"01");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-DISABLE-L03, BLCOL-DISABLE-L04, BLCOL-DISABLE-L05.
    function test_givenAnyCoreState_whenDisabled_thenDependenciesIgnored(
        bool active_,
        bool enabled_
    ) public givenCollateralEnabled {
        _setPolicyState(policy, active_, enabled_);
        vm.expectEmit(address(_collateral));
        emit IEnabler.Disabled();
        vm.expectEmit(address(_collateral));
        emit IEnablerV2.Transition(address(this), false, "", uint48(block.timestamp));
        _collateral.disable("");
        assertFalse(_collateral.isEnabled(), "Core state cannot prevent pause");
        _assertAccountingPreserved();
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
