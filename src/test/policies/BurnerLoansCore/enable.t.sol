// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {StdStorage, stdStorage} from "@forge-std-1.16.2/StdStorage.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";

contract BurnerLoansCoreEnableTest is BurnerLoansCoreTest {
    using stdStorage for StdStorage;

    // Scenarios: BLCORE-ENABLE-A01.
    function test_givenReadyGraph_whenEnabled(address caller_) public {
        _grantAdmin(caller_);
        _deposit(2000e6);
        _borrow(100e9);
        _core.disable("");
        bytes32 ledger = _ledger();
        vm.expectEmit(false, false, false, true, address(_core));
        emit IEnabler.Enabled();
        vm.expectEmit(true, false, false, true, address(_core));
        emit IEnablerV2.Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
        vm.prank(caller_);
        _core.enable("");
        assertTrue(_core.isEnabled(), "Core enabled");
        assertEq(_core.lastTransitionAt(), vm.getBlockTimestamp(), "Exact transition timestamp");
        assertEq(_ledger(), ledger, "Transition preserves live debt and custody");
    }

    // Scenarios: BLCORE-ENABLE-A02.
    function test_givenUnauthorized_whenEnabled_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _core.disable("");
        bytes32 before = _state();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _core.enable("");
        assertEq(_state(), before, "Unauthorized enable preserves state");
    }

    // Scenarios: BLCORE-ENABLE-L01.
    function test_givenAlreadyEnabled_whenEnabled_reverts(address caller_, bool active_) public {
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _core.enable("");
    }

    // Scenarios: BLCORE-ENABLE-L02.
    function test_givenCoreInactive_whenEnabled_reverts(address caller_) public {
        _grantAdmin(caller_);
        _setCoreLifecycle(false, false);
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        vm.prank(caller_);
        _core.enable("");
        assertEq(_state(), before, "Own inactivity cannot be bypassed");
    }

    // Scenarios: BLCORE-ENABLE-D01, BLCORE-ENABLE-D02, BLCORE-ENABLE-D03.
    function test_givenDepositManagerUnavailable_whenEnabled_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _grantAdmin(caller_);
        vm.assume(!active_ || !enabled_);
        _deposit(2000e6);
        _borrow(100e9);
        _core.disable("");
        if (!enabled_) IEnabler(address(_depositManager)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_depositManager));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_depositManager)
            )
        );
        vm.prank(caller_);
        _core.enable("");
        assertEq(_state(), before, "Unavailable dependency preserves Core and loans");
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_depositManager));
        if (!enabled_) IEnabler(address(_depositManager)).enable("");
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        _core.enable("");
        assertTrue(_core.isEnabled(), "Restoring only failed flags permits retry");
        assertEq(_ledger(), ledger, "Retry moves no custody");
    }

    // Scenarios: BLCORE-ENABLE-D08.
    function test_givenDepositManagerWrongKernel_whenEnabled_reverts(address caller_) public {
        _grantAdmin(caller_);
        _core.disable("");
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0))
        );
        bytes32 before = _state();
        _expectDependencyKernelMismatch(address(_depositManager), address(0));
        vm.prank(caller_);
        _core.enable("");
        assertEq(_state(), before, "Wrong binding cannot transition");
    }

    // Scenarios: BLCORE-ENABLE-D04, BLCORE-ENABLE-D05, BLCORE-ENABLE-D06.
    function test_givenInventoryUnavailable_whenEnabled_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _grantAdmin(caller_);
        vm.assume(!active_ || !enabled_);
        _deposit(2000e6);
        _borrow(100e9);
        _core.disable("");
        if (!enabled_) IEnabler(address(_inventory)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_inventory));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_inventory)
            )
        );
        vm.prank(caller_);
        _core.enable("");
        assertEq(_state(), before, "Unavailable dependency preserves Core and loans");
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_inventory));
        if (!enabled_) IEnabler(address(_inventory)).enable("");
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        _core.enable("");
        assertTrue(_core.isEnabled(), "Restoring only failed flags permits retry");
        assertEq(_ledger(), ledger, "Retry moves no custody");
    }

    // Scenarios: BLCORE-ENABLE-D09.
    function test_givenInventoryWrongKernel_whenEnabled_reverts(address caller_) public {
        _grantAdmin(caller_);
        _core.disable("");
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0))
        );
        bytes32 before = _state();
        _expectDependencyKernelMismatch(address(_inventory), address(0));
        vm.prank(caller_);
        _core.enable("");
        assertEq(_state(), before, "Wrong binding cannot transition");
    }

    // Scenarios: BLCORE-ENABLE-D07, BLCORE-ENABLE-D24, BLCORE-ENABLE-D26.
    function test_givenPayoutUnavailable_whenEnabled_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _grantAdmin(caller_);
        vm.assume(!active_ || !enabled_);
        _deposit(2000e6);
        _borrow(100e9);
        _core.disable("");
        if (!enabled_) IEnabler(address(_payout)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_payout));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_payout)
            )
        );
        vm.prank(caller_);
        _core.enable("");
        assertEq(_state(), before, "Unavailable dependency preserves Core and loans");
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        if (!enabled_) IEnabler(address(_payout)).enable("");
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        _core.enable("");
        assertTrue(_core.isEnabled(), "Restoring only failed flags permits retry");
        assertEq(_ledger(), ledger, "Retry moves no custody");
    }

    // Scenarios: BLCORE-ENABLE-D10.
    function test_givenPayoutWrongKernel_whenEnabled_reverts(address caller_) public {
        _grantAdmin(caller_);
        _core.disable("");
        vm.mockCall(address(_payout), abi.encodeWithSignature("kernel()"), abi.encode(address(0)));
        bytes32 before = _state();
        _expectDependencyKernelMismatch(address(_payout), address(0));
        vm.prank(caller_);
        _core.enable("");
        assertEq(_state(), before, "Wrong binding cannot transition");
    }

    // Scenarios: BLCORE-ENABLE-D21, BLCORE-ENABLE-D20, BLCORE-ENABLE-D22.
    function test_givenRiskUnavailable_whenEnabled_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _grantAdmin(caller_);
        vm.assume(!active_ || !enabled_);
        _deposit(2000e6);
        _borrow(100e9);
        _core.disable("");
        if (!enabled_) IEnabler(address(_risk)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_risk)
            )
        );
        vm.prank(caller_);
        _core.enable("");
        assertEq(_state(), before, "Unavailable dependency preserves Core and loans");
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_risk));
        if (!enabled_) IEnabler(address(_risk)).enable("");
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        _core.enable("");
        assertTrue(_core.isEnabled(), "Restoring only failed flags permits retry");
        assertEq(_ledger(), ledger, "Retry moves no custody");
    }

    // Scenarios: BLCORE-ENABLE-D32.
    function test_givenRiskWrongKernel_whenEnabled_reverts(address caller_) public {
        _grantAdmin(caller_);
        _core.disable("");
        vm.mockCall(address(_risk), abi.encodeWithSignature("kernel()"), abi.encode(address(0)));
        bytes32 before = _state();
        _expectDependencyKernelMismatch(address(_risk), address(0));
        vm.prank(caller_);
        _core.enable("");
        assertEq(_state(), before, "Wrong binding cannot transition");
    }

    // Scenarios: BLCORE-ENABLE-D11.
    function test_givenRiskUnset_whenEnabled_reverts(address caller_) public {
        _grantAdmin(caller_);
        _core.disable("");
        stdstore.target(address(_core)).sig(bytes4(keccak256("risk()"))).checked_write(address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        _core.enable("");
        assertFalse(_core.isEnabled(), "Unset service cannot enable");
    }

    // Scenarios: BLCORE-ENABLE-D33.
    function test_givenInventoryUnset_whenEnabled_reverts(address caller_) public {
        _grantAdmin(caller_);
        _core.disable("");
        stdstore.target(address(_core)).sig(bytes4(keccak256("inventory()"))).checked_write(
            address(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidInventory.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        _core.enable("");
        assertFalse(_core.isEnabled(), "Unset service cannot enable");
    }

    // Scenarios: BLCORE-ENABLE-D34.
    function test_givenPayoutUnset_whenEnabled_reverts(address caller_) public {
        _grantAdmin(caller_);
        _core.disable("");
        stdstore.target(address(_core)).sig(bytes4(keccak256("payout()"))).checked_write(
            address(0)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidPayout.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        _core.enable("");
        assertFalse(_core.isEnabled(), "Unset service cannot enable");
    }

    // Scenarios: BLCORE-ENABLE-D14, BLCORE-ENABLE-D18.
    function test_givenConfigUnavailable_whenEnabled(
        address caller_,
        bool active_,
        bool enabled_,
        bool wrongKernel_
    ) public {
        _grantAdmin(caller_);
        _core.disable("");
        if (!enabled_) _config.disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        if (wrongKernel_)
            vm.mockCall(
                address(_config),
                abi.encodeWithSignature("kernel()"),
                abi.encode(address(0))
            );
        vm.expectCall(address(_config), abi.encodeWithSignature("kernel()"), uint64(0));
        vm.prank(caller_);
        _core.enable("");
        assertTrue(_core.isEnabled(), "Upstream Config is not operational dependency");
    }

    // Scenarios: BLCORE-ENABLE-C01.
    function test_givenBusyCore_whenCaughtEnable_reverts() public {
        _core.disable("");
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("enable(bytes)", bytes("")),
            false
        );
        uint48 transition = _core.lastTransitionAt();
        _core.rescue(address(token), _recipient);
        assertFalse(_core.isEnabled(), "Callback cannot enable during rescue");
        assertEq(_core.lastTransitionAt(), transition, "No nested transition");
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized callback reaches guard"
        );
        assertEq(token.balanceOf(_recipient), 1, "Caught rejection rescues once");
    }

    // Scenarios: BLCORE-ENABLE-C02.
    function test_givenBusyCore_whenPropagatedEnable_reverts() public {
        _core.disable("");
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("enable(bytes)", bytes("")),
            true
        );
        uint48 transition = _core.lastTransitionAt();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _core.rescue(address(token), _recipient);
        assertFalse(_core.isEnabled(), "Callback cannot enable during rescue");
        assertEq(_core.lastTransitionAt(), transition, "No nested transition");
        assertEq(token.balanceOf(address(_core)), 1, "Propagated guard rolls back rescue");
    }

    // Scenarios: BLCORE-ENABLE-I01.
    function test_givenPayload_whenEnabled_reverts(bytes memory payload_) public {
        vm.assume(payload_.length > 0);
        _core.disable("");
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        _core.enable(payload_);
        assertFalse(_core.isEnabled(), "Invalid payload cannot transition");
    }

    // Scenarios: BLCORE-ENABLE-I02.
    function test_givenEnabledCoreAndPayload_whenEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        _core.enable(hex"01");
    }

    // Scenarios: BLCORE-ENABLE-I03.
    function test_givenUnauthorizedAndPayload_whenEnabled_reverts(address caller_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _core.disable("");
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _core.enable(hex"01");
    }

    // Scenarios: BLCORE-ENABLE-I04.
    function test_givenBusyCoreAndPayload_whenEnabled_reverts() public {
        _core.disable("");
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("enable(bytes)", hex"01"),
            false
        );
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector,
            "Enable validates payload before busy hook"
        );
    }

    // Scenarios: BLCORE-ENABLE-L03.
    function test_givenNeverConfigured_whenEnabled_reverts() public {
        BurnerLoansCore fresh = new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            _depositManager
        );
        vm.expectRevert(bytes(""));
        fresh.enable("");
        assertFalse(fresh.isEnabled(), "Uninitialized role dependency has no ABI result");
    }
}
