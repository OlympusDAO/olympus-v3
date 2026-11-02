// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";

import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansSeize} from "src/policies/burnerloans/BurnerLoansSeize.sol";
import {BurnerLoansSeizeLifecycleTest} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeLifecycleTest.sol";

// Literals are independent expected values and boundary seeds.
// Bounded seed loops intentionally call external contracts.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

contract BurnerLoansSeizeEnableTest is BurnerLoansSeizeLifecycleTest {
    // Scenarios: BLLIQ-ENABLE-L01.
    function test_givenEnabled_whenAnyCallerEnables_reverts(
        address caller_,
        bool active_,
        bool zeroHistory_
    ) public {
        _setEnabledHistory(zeroHistory_);
        _mockUnavailableCoreViews();
        _setPolicyState(_liquidation, active_, true);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _liquidation.enable("");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-ENABLE-L02.
    function test_givenInactive_whenEnabled_reverts() public {
        _setPolicyState(_liquidation, false, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_liquidation)
            )
        );
        _liquidation.enable("");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-ENABLE-A02.
    function test_givenDisabled_whenUnauthorizedEnables_reverts(address caller_) public {
        _liquidation.disable("");
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _liquidation.enable("");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-ENABLE-A01.
    function test_givenDisabled_whenAdminEnables_thenExactTransition(address caller_) public {
        vm.assume(caller_ != address(0));
        _liquidation.disable("");
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.warp(456);
        _expectEnabledTransition(caller_);
        vm.prank(caller_);
        _liquidation.enable("");
        assertTrue(_liquidation.isEnabled(), "Admin enables action");
        assertEq(_liquidation.lastTransitionAt(), 456, "Enable records timestamp");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-ENABLE-I01.
    function test_whenNonemptyEnableData_reverts(bytes memory data_) public {
        vm.assume(data_.length != 0);
        _liquidation.disable("");
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        _liquidation.enable(data_);
        assertFalse(_liquidation.isEnabled(), "Rejected payload cannot enable");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-ENABLE-I02.
    function test_givenEnabled_whenNonemptyEnableData_thenStateWins(address caller_) public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _liquidation.enable(hex"01");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-ENABLE-I03.
    function test_givenDisabled_whenUnauthorizedNonemptyEnable_thenAuthWins(
        address caller_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _liquidation.disable("");
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _liquidation.enable(hex"01");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-ENABLE-D04.
    function test_givenCoreReportedKernelChanges_whenEnabled_thenKernelMismatch() public {
        _liquidation.disable("");
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
        _liquidation.enable("");
        vm.clearMockedCalls();
        _assertLoansPreserved();
    }

    function test_givenInventoryKernelChanged_whenEnabled_reverts() public {
        _liquidation.disable("");
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
        _liquidation.enable("");
    }

    // Scenarios: BLLIQ-ENABLE-L03.
    function test_givenSettlementRoleRevoked_whenEnabled_reverts() public {
        _liquidation.disable("");
        _rolesAdmin.revokeRole(_SETTLEMENT_ROLE, address(_liquidation));
        uint48 last = _liquidation.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, _SETTLEMENT_ROLE)
        );
        _liquidation.enable("");
        assertFalse(_liquidation.isEnabled(), "Missing settlement authority blocks activation");
        assertEq(_liquidation.lastTransitionAt(), last, "Failed activation preserves history");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-ENABLE-L04.
    function test_givenNeverActivated_whenEnabled_thenInitializationPrecedence(
        address caller_
    ) public {
        BurnerLoansSeize fresh = new BurnerLoansSeize(_kernel, _core);
        // Unset ROLES returns no ABI boolean; this dependency has no stable typed error.
        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        fresh.enable("");
        assertFalse(fresh.isEnabled(), "Fresh action remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Rejected transition cannot initialize history");
    }

    // Scenarios: BLLIQ-ENABLE-L01.
    function test_givenZeroTransitionHistory_whenAlreadyEnabled_thenStateWins() public {
        test_givenEnabled_whenAnyCallerEnables_reverts(address(0), true, true);
    }

    // Scenarios: BLLIQ-ENABLE-D09, BLLIQ-ENABLE-D10, BLLIQ-ENABLE-D11, BLLIQ-ENABLE-D12.
    function test_givenPayoutUnavailable_whenEnabled_thenRejectAndRetry(
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _liquidation.disable("");
        _setPolicyState(_payout, active_, enabled_);
        uint48 last = _liquidation.lastTransitionAt();
        _expectDependencyUnavailable(_payout);

        _liquidation.enable("");
        _assertActivationRejected(last);
        _restorePolicyState(_payout, active_, enabled_);
        _expectEnabledTransition(address(this));

        _liquidation.enable("");
        _assertEnabled();
    }

    // Scenarios: BLLIQ-ENABLE-D09, BLLIQ-ENABLE-D10, BLLIQ-ENABLE-D11, BLLIQ-ENABLE-D12.
    function test_givenEachUnavailablePayoutState_whenEnabled_thenRejectAndRetry() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPayoutUnavailable_whenEnabled_thenRejectAndRetry(true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore Payout for inactive state");
        test_givenPayoutUnavailable_whenEnabled_thenRejectAndRetry(false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore Payout for both flags off");
        test_givenPayoutUnavailable_whenEnabled_thenRejectAndRetry(false, false);
    }

    // Scenarios: BLLIQ-ENABLE-D01, BLLIQ-ENABLE-D02, BLLIQ-ENABLE-D03.
    function test_givenCoreUnavailable_whenEnabled_thenRejectAndRetry(
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _liquidation.disable("");
        _setPolicyState(_core, active_, enabled_);

        uint48 last = _liquidation.lastTransitionAt();
        _expectDependencyUnavailable(_core);

        _liquidation.enable("");
        _assertActivationRejected(last);
        _restorePolicyState(_core, active_, enabled_);
        _expectEnabledTransition(address(this));

        _liquidation.enable("");
        _assertEnabled();
    }

    // Scenarios: BLLIQ-ENABLE-D01, BLLIQ-ENABLE-D02, BLLIQ-ENABLE-D03.
    function test_givenEachUnavailableCoreState_whenEnabled_thenRejectAndRetry() public {
        bool[3] memory active = [true, false, false];
        bool[3] memory enabled = [false, true, false];
        for (uint256 state; state < 3; ++state) {
            uint256 checkpoint = vm.snapshotState();
            test_givenCoreUnavailable_whenEnabled_thenRejectAndRetry(active[state], enabled[state]);
            assertTrue(vm.revertToState(checkpoint), "Restore prerequisite for each state seed");
        }
    }

    // Scenarios: BLLIQ-ENABLE-D05, BLLIQ-ENABLE-D06, BLLIQ-ENABLE-D07, BLLIQ-ENABLE-D08.
    function test_givenInventoryUnavailable_whenEnabled_thenRejectAndRetry(
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _liquidation.disable("");
        _setPolicyState(_inventory, active_, enabled_);
        assertTrue(_core.isEnabled(), "Core remains enabled during independent Inventory drift");
        uint48 last = _liquidation.lastTransitionAt();
        _expectDependencyUnavailable(_inventory);

        _liquidation.enable("");
        _assertActivationRejected(last);
        _restorePolicyState(_inventory, active_, enabled_);
        _expectEnabledTransition(address(this));

        _liquidation.enable("");
        _assertEnabled();
    }

    // Scenarios: BLLIQ-ENABLE-D05, BLLIQ-ENABLE-D06, BLLIQ-ENABLE-D07, BLLIQ-ENABLE-D08.
    function test_givenEachUnavailableInventoryState_whenEnabled_thenRejectAndRetry() public {
        bool[3] memory active = [true, false, false];
        bool[3] memory enabled = [false, true, false];
        for (uint256 state; state < 3; ++state) {
            uint256 checkpoint = vm.snapshotState();
            test_givenInventoryUnavailable_whenEnabled_thenRejectAndRetry(
                active[state],
                enabled[state]
            );
            assertTrue(vm.revertToState(checkpoint), "Restore prerequisite for each state seed");
        }
    }

    // Scenarios: BLLIQ-ENABLE-I01.
    function test_whenPayloadBoundarySeedsProvided_reverts() public {
        bytes[4] memory payloads = [
            bytes(hex"00"),
            bytes(hex"01"),
            abi.encode(uint256(0)),
            new bytes(256)
        ];
        for (uint256 i; i < payloads.length; ++i) {
            uint256 checkpoint = vm.snapshotState();
            test_whenNonemptyEnableData_reverts(payloads[i]);
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore enabled state and roles between payload seeds"
            );
        }
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant)
