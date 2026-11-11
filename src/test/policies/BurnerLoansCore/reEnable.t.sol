// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {StdStorage, stdStorage} from "@forge-std-1.16.2/StdStorage.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";

contract BurnerLoansCoreReEnableTest is BurnerLoansCoreTest {
    uint256 internal constant _ABI_WORD_BYTES = 32;
    using stdStorage for StdStorage;

    // Scenarios: BLCORE-REENABLE-P01.
    function test_givenReadyGraph_whenEnabled(address caller_, bool admin_, bool overlap_) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
        _deposit(2000e6);
        _borrow(100e9);
        _core.disable("");
        bytes32 ledger = _ledger();
        vm.expectEmit(false, false, false, true, address(_core));
        emit IEnabler.Enabled();
        vm.expectEmit(true, false, false, true, address(_core));
        emit IEnablerV2.Transition(caller_, true, "", uint48(vm.getBlockTimestamp()));
        vm.prank(caller_);
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Core enabled");
        assertEq(_core.lastTransitionAt(), vm.getBlockTimestamp(), "Exact transition timestamp");
        assertEq(_ledger(), ledger, "Transition preserves live debt and custody");
    }

    // Scenarios: BLCORE-REENABLE-A01.
    function test_givenUnauthorized_whenEnabled_reverts(address caller_) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _core.disable("");
        bytes32 before = _state();
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _core.reEnable();
        assertEq(_state(), before, "Unauthorized enable preserves state");
    }

    // Scenarios: BLCORE-REENABLE-L01.
    function test_givenAlreadyEnabled_whenEnabled_reverts(address caller_, bool active_) public {
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _core.reEnable();
    }

    // Scenarios: BLCORE-REENABLE-L03.
    function test_givenCoreInactive_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
        _setCoreLifecycle(false, false);
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        vm.prank(caller_);
        _core.reEnable();
        assertEq(_state(), before, "Own inactivity cannot be bypassed");
    }

    // Scenarios: BLCORE-REENABLE-D01, BLCORE-REENABLE-D02, BLCORE-REENABLE-D03.
    function test_givenDepositManagerUnavailable_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_,
        bool active_,
        bool enabled_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
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
        _core.reEnable();
        assertEq(_state(), before, "Unavailable dependency preserves Core and loans");
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_depositManager));
        if (!enabled_) IEnabler(address(_depositManager)).enable("");
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Restoring only failed flags permits retry");
        assertEq(_ledger(), ledger, "Retry moves no custody");
    }

    // Scenarios: BLCORE-REENABLE-D08.
    function test_givenDepositManagerWrongKernel_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
        _core.disable("");
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0))
        );
        bytes32 before = _state();
        _expectDependencyKernelMismatch(address(_depositManager), address(0));
        vm.prank(caller_);
        _core.reEnable();
        assertEq(_state(), before, "Wrong binding cannot transition");
    }

    // Scenarios: BLCORE-REENABLE-D04, BLCORE-REENABLE-D05, BLCORE-REENABLE-D06.
    function test_givenInventoryUnavailable_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_,
        bool active_,
        bool enabled_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
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
        _core.reEnable();
        assertEq(_state(), before, "Unavailable dependency preserves Core and loans");
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_inventory));
        if (!enabled_) IEnabler(address(_inventory)).enable("");
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Restoring only failed flags permits retry");
        assertEq(_ledger(), ledger, "Retry moves no custody");
    }

    // Scenarios: BLCORE-REENABLE-D09.
    function test_givenInventoryWrongKernel_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
        _core.disable("");
        bytes32 before = _state();
        uint48 transition = _core.lastTransitionAt();
        Kernel other = new Kernel();
        vm.prank(address(_kernel));
        _inventory.changeKernel(other);
        assertTrue(_kernel.isPolicyActive(_inventory), "Old Kernel retains stale membership");
        _expectDependencyKernelMismatch(address(_inventory), address(other));
        vm.prank(caller_);
        _core.reEnable();
        assertFalse(_core.isEnabled(), "Foreign reported Kernel rejects stale active membership");
        assertEq(_core.lastTransitionAt(), transition, "Rejection preserves transition history");
        vm.prank(address(other));
        _inventory.changeKernel(_kernel);
        assertEq(_state(), before, "Rejection preserves accounting and selected services");
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Restored Kernel permits retry");
        assertEq(_ledger(), ledger, "Retry preserves accounting and custody");
    }

    // Scenarios: BLCORE-REENABLE-D35.
    function test_givenInventoryMalformedStatus_whenEnabled_reverts(
        bytes memory data_,
        bool enabledGetter_
    ) public {
        vm.assume(data_.length != _ABI_WORD_BYTES);
        _core.disable("");
        vm.mockCall(
            address(_inventory),
            enabledGetter_
                ? abi.encodeWithSignature("isEnabled()")
                : abi.encodeWithSignature("kernel()"),
            data_
        );
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_inventory)
            )
        );
        _core.reEnable();
        assertEq(_state(), before, "Malformed status cannot change Core state");
        vm.clearMockedCalls();
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Restored status permits retry");
    }

    // Scenarios: BLCORE-REENABLE-D07, BLCORE-REENABLE-D24, BLCORE-REENABLE-D26.
    function test_givenPayoutUnavailable_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_,
        bool active_,
        bool enabled_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
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
        _core.reEnable();
        assertEq(_state(), before, "Unavailable dependency preserves Core and loans");
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        if (!enabled_) IEnabler(address(_payout)).enable("");
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Restoring only failed flags permits retry");
        assertEq(_ledger(), ledger, "Retry moves no custody");
    }

    // Scenarios: BLCORE-REENABLE-D10.
    function test_givenPayoutWrongKernel_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
        _core.disable("");
        bytes32 before = _state();
        uint48 transition = _core.lastTransitionAt();
        Kernel other = new Kernel();
        vm.prank(address(_kernel));
        _payout.changeKernel(other);
        assertTrue(_kernel.isPolicyActive(_payout), "Old Kernel retains stale membership");
        _expectDependencyKernelMismatch(address(_payout), address(other));
        vm.prank(caller_);
        _core.reEnable();
        assertFalse(_core.isEnabled(), "Foreign reported Kernel rejects stale active membership");
        assertEq(_core.lastTransitionAt(), transition, "Rejection preserves transition history");
        vm.prank(address(other));
        _payout.changeKernel(_kernel);
        assertEq(_state(), before, "Rejection preserves accounting and selected services");
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Restored Kernel permits retry");
        assertEq(_ledger(), ledger, "Retry preserves accounting and custody");
    }

    // Scenarios: BLCORE-REENABLE-D36.
    function test_givenPayoutMalformedStatus_whenEnabled_reverts(
        bytes memory data_,
        bool enabledGetter_
    ) public {
        vm.assume(data_.length != _ABI_WORD_BYTES);
        _core.disable("");
        vm.mockCall(
            address(_payout),
            enabledGetter_
                ? abi.encodeWithSignature("isEnabled()")
                : abi.encodeWithSignature("kernel()"),
            data_
        );
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_payout)
            )
        );
        _core.reEnable();
        assertEq(_state(), before, "Malformed status cannot change Core state");
        vm.clearMockedCalls();
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Restored status permits retry");
    }

    // Scenarios: BLCORE-REENABLE-D21, BLCORE-REENABLE-D20, BLCORE-REENABLE-D22.
    function test_givenRiskUnavailable_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_,
        bool active_,
        bool enabled_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
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
        _core.reEnable();
        assertEq(_state(), before, "Unavailable dependency preserves Core and loans");
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_risk));
        if (!enabled_) IEnabler(address(_risk)).enable("");
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Restoring only failed flags permits retry");
        assertEq(_ledger(), ledger, "Retry moves no custody");
    }

    // Scenarios: BLCORE-REENABLE-D32.
    function test_givenRiskWrongKernel_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
        _core.disable("");
        bytes32 before = _state();
        uint48 transition = _core.lastTransitionAt();
        Kernel other = new Kernel();
        vm.prank(address(_kernel));
        _risk.changeKernel(other);
        assertTrue(_kernel.isPolicyActive(_risk), "Old Kernel retains stale membership");
        _expectDependencyKernelMismatch(address(_risk), address(other));
        vm.prank(caller_);
        _core.reEnable();
        assertFalse(_core.isEnabled(), "Foreign reported Kernel rejects stale active membership");
        assertEq(_core.lastTransitionAt(), transition, "Rejection preserves transition history");
        vm.prank(address(other));
        _risk.changeKernel(_kernel);
        assertEq(_state(), before, "Rejection preserves accounting and selected services");
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Restored Kernel permits retry");
        assertEq(_ledger(), ledger, "Retry preserves accounting and custody");
    }

    // Scenarios: BLCORE-REENABLE-D37.
    function test_givenRiskMalformedStatus_whenEnabled_reverts(
        bytes memory data_,
        bool enabledGetter_
    ) public {
        vm.assume(data_.length != _ABI_WORD_BYTES);
        _core.disable("");
        vm.mockCall(
            address(_risk),
            enabledGetter_
                ? abi.encodeWithSignature("isEnabled()")
                : abi.encodeWithSignature("kernel()"),
            data_
        );
        bytes32 before = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_risk)
            )
        );
        _core.reEnable();
        assertEq(_state(), before, "Malformed status cannot change Core state");
        vm.clearMockedCalls();
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Restored status permits retry");
    }

    // Scenarios: BLCORE-REENABLE-D11.
    function test_givenRiskUnset_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
        _core.disable("");
        stdstore.target(address(_core)).sig(bytes4(keccak256("risk()"))).checked_write(address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidRisk.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        _core.reEnable();
        assertFalse(_core.isEnabled(), "Unset service cannot enable");
    }

    // Scenarios: BLCORE-REENABLE-D33.
    function test_givenInventoryUnset_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
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
        _core.reEnable();
        assertFalse(_core.isEnabled(), "Unset service cannot enable");
    }

    // Scenarios: BLCORE-REENABLE-D34.
    function test_givenPayoutUnset_whenEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
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
        _core.reEnable();
        assertFalse(_core.isEnabled(), "Unset service cannot enable");
    }

    // Scenarios: BLCORE-REENABLE-D14, BLCORE-REENABLE-D18.
    function test_givenConfigUnavailable_whenEnabled(
        address caller_,
        bool admin_,
        bool overlap_,
        bool active_,
        bool enabled_,
        bool wrongKernel_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
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
        _core.reEnable();
        assertTrue(_core.isEnabled(), "Upstream Config is not operational dependency");
    }

    // Scenarios: BLCORE-REENABLE-C01.
    function test_givenBusyCore_whenCaughtEnable_reverts() public {
        _core.disable("");
        CoreCallbackToken token = _armRescue(abi.encodeWithSignature("reEnable()"), false);
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

    // Scenarios: BLCORE-REENABLE-C02.
    function test_givenBusyCore_whenPropagatedEnable_reverts() public {
        _core.disable("");
        CoreCallbackToken token = _armRescue(abi.encodeWithSignature("reEnable()"), true);
        uint48 transition = _core.lastTransitionAt();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _core.rescue(address(token), _recipient);
        assertFalse(_core.isEnabled(), "Callback cannot enable during rescue");
        assertEq(_core.lastTransitionAt(), transition, "No nested transition");
        assertEq(token.balanceOf(address(_core)), 1, "Propagated guard rolls back rescue");
    }

    // Scenarios: BLCORE-REENABLE-L02, BLCORE-REENABLE-L04.
    function test_givenNeverEnabled_whenReEnabled_reverts(address caller_, bool active_) public {
        BurnerLoansCore fresh = new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            _depositManager
        );
        if (active_) _kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
        assertEq(fresh.lastTransitionAt(), 0, "Never enabled check precedes role reads");
    }

    // Scenarios: BLCORE-REENABLE-A02.
    function test_givenUnauthorizedAndExpiredGrace_whenReEnabled_reverts(address caller_) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _core.disable("");
        _risk.disable("");
        vm.warp(uint256(_core.lastTransitionAt()) + _core.gracePeriod() + 1);
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _core.reEnable();
    }

    // Scenarios: BLCORE-REENABLE-P01, BLCORE-REENABLE-P02.
    function test_givenInclusiveGrace_whenReEnabled(
        address caller_,
        bool admin_,
        bool overlap_,
        uint48 last_,
        uint32 period_,
        uint48 now_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
        period_ = uint32(bound(period_, 1, type(uint32).max));
        last_ = _bounds48(last_, 1, type(uint48).max - period_);
        _core.setGracePeriod(period_);
        vm.warp(last_);
        _core.disable("");
        uint48 deadline = last_ + period_;
        now_ = _bounds48(now_, last_, deadline);
        vm.warp(now_);
        vm.expectEmit(false, false, false, true, address(_core));
        emit IEnabler.Enabled();
        vm.expectEmit(true, false, false, true, address(_core));
        emit IEnablerV2.Transition(caller_, true, "", now_);
        vm.prank(caller_);
        _core.reEnable();
        assertEq(_core.lastTransitionAt(), now_, "Inclusive grace transition timestamp");
        assertTrue(_core.isEnabled(), "Within grace restores Core");
    }

    // Scenarios: BLCORE-REENABLE-P03.
    function test_givenExpiredGrace_whenReEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_,
        uint48 last_,
        uint32 period_,
        uint48 now_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
        period_ = uint32(bound(period_, 1, type(uint32).max));
        last_ = _bounds48(last_, 1, type(uint48).max - period_ - 1);
        _core.setGracePeriod(period_);
        vm.warp(last_);
        _core.disable("");
        uint48 deadline = last_ + period_;
        now_ = _bounds48(now_, deadline + 1, type(uint48).max);
        vm.warp(now_);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        _core.reEnable();
        assertFalse(_core.isEnabled(), "Expired grace leaves disabled");
        assertEq(_core.lastTransitionAt(), last_, "Failed retry preserves disable timestamp");
    }

    // Scenarios: BLCORE-REENABLE-N01.
    function test_givenDeadlineOverflow_whenReEnabled_reverts(
        address caller_,
        bool admin_,
        bool overlap_,
        uint48 last_,
        uint32 period_
    ) public {
        _grantLifecycleCaller(caller_, BURNER_LOANS_ADMIN_ROLE, admin_, overlap_);
        period_ = uint32(bound(period_, 1, type(uint32).max));
        last_ = _bounds48(last_, type(uint48).max - period_ + 1, type(uint48).max);
        _core.setGracePeriod(period_);
        vm.warp(last_);
        _core.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(last_) + period_
            )
        );
        vm.prank(caller_);
        _core.reEnable();
        assertEq(_core.lastTransitionAt(), last_, "Widened overflow preserves timestamp");
    }

    // Scenarios: BLCORE-REENABLE-I01.
    function test_givenBusyCoreAndExpiredGrace_whenReEnabled_reverts() public {
        _core.disable("");
        vm.warp(uint256(_core.lastTransitionAt()) + _core.gracePeriod() + 1);
        CoreCallbackToken token = _armRescue(abi.encodeWithSignature("reEnable()"), false);
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Settlement guard precedes grace expiry"
        );
    }

    // Scenarios: BLCORE-REENABLE-P01, BLCORE-REENABLE-P02, BLCORE-REENABLE-P03, BLCORE-REENABLE-N01.
    function test_whenGraceBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenInclusiveGrace_whenReEnabled(_recipient, true, false, 1, 1, 1);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenInclusiveGrace_whenReEnabled(
            _recipient,
            false,
            false,
            type(uint48).max - 1,
            1,
            type(uint48).max
        );
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenInclusiveGrace_whenReEnabled(
            _recipient,
            true,
            true,
            1,
            type(uint32).max,
            type(uint32).max
        );
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenExpiredGrace_whenReEnabled_reverts(_recipient, true, false, 1, 1, 3);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenExpiredGrace_whenReEnabled_reverts(
            _recipient,
            false,
            false,
            1,
            1,
            type(uint48).max
        );
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_givenDeadlineOverflow_whenReEnabled_reverts(
            _recipient,
            true,
            true,
            type(uint48).max,
            1
        );
        vm.revertToState(snapshot);
        test_givenDeadlineOverflow_whenReEnabled_reverts(
            _recipient,
            true,
            false,
            type(uint48).max,
            type(uint32).max
        );
    }
}
