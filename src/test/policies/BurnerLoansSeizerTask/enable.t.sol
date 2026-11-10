// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansSeizerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansSeizerTask.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansSeizerTaskTest} from "./BurnerLoansSeizerTaskTest.sol";
import {Actions} from "src/Kernel.sol";

contract BurnerLoansSeizerTaskEnableTest is BurnerLoansSeizerTaskTest {
    error CoreLifecycleReadFailed();

    // Scenarios: BLSEIZ-ENABLE-D08.
    function test_givenKernelDrift_whenEnabled_reverts(address otherKernel_) public {
        vm.assume(otherKernel_ != address(_kernel));
        _task.disable("");
        vm.mockCall(
            address(_liquidation),
            abi.encodeCall(_liquidation.kernel, ()),
            abi.encode(otherKernel_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_liquidation),
                address(_kernel),
                otherKernel_
            )
        );
        _task.enable("");
        assertFalse(_task.isEnabled(), "Kernel mismatch preserves disabled state");
        vm.clearMockedCalls();
        _task.enable("");
        assertTrue(_task.isEnabled(), "Restoring Kernel identity permits retry");
    }

    // Scenarios: BLSEIZ-ENABLE-D09.
    function test_givenLensCoreDrift_whenEnabled_reverts(address otherCore_) public {
        vm.assume(otherCore_ != address(_core));
        _task.disable("");
        vm.mockCall(
            address(_lens),
            abi.encodeCall(IBurnerLoansCoreBound.core, ()),
            abi.encode(otherCore_)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizer_InvalidLens.selector,
                address(_lens)
            )
        );
        _task.enable("");
        assertFalse(_task.isEnabled(), "Lens mismatch preserves disabled state");
        vm.clearMockedCalls();
        _task.enable("");
        assertTrue(_task.isEnabled(), "Restoring Lens binding permits retry");
    }

    // Scenarios: BLSEIZ-ENABLE-D02, BLSEIZ-ENABLE-D05, BLSEIZ-ENABLE-D06.
    function test_givenSeizeInactiveOrDisabled_whenEnabled_reverts(
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _task.disable("");
        if (!enabled_) _liquidation.disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_liquidation)
            )
        );
        _task.enable("");
        assertFalse(_task.isEnabled(), "Unavailable Seize preserves disabled state");
        if (!active_) _kernel.executeAction(Actions.ActivatePolicy, address(_liquidation));
        if (!enabled_) _liquidation.enable("");
        _task.enable("");
        assertTrue(_task.isEnabled(), "Restoring Seize permits retry");
    }

    function test_givenSeizeReady_whenAdminEnables() public {
        _task.disable("");
        _task.enable("");
        assertTrue(_task.isEnabled(), "Ready Seize permits enable");
    }

    function test_givenCoreLifecycleUnreadable_whenEnabled_succeeds() public {
        _task.disable("");
        bytes memory kernelRead = abi.encodeCall(_core.kernel, ());
        bytes memory enabledRead = abi.encodeCall(_core.isEnabled, ());
        vm.mockCallRevert(
            address(_core),
            kernelRead,
            abi.encodeWithSelector(CoreLifecycleReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_core),
            enabledRead,
            abi.encodeWithSelector(CoreLifecycleReadFailed.selector)
        );
        vm.expectCall(address(_core), kernelRead, uint64(0));
        vm.expectCall(address(_core), enabledRead, uint64(0));
        _task.enable("");
        assertTrue(_task.isEnabled(), "Activation checks Core compatibility without its lifecycle");
    }

    // Scenarios: BLSEIZ-ENABLE-D12.
    function test_givenMissingCoreInterface_whenActivated_reverts() public {
        _task.disable("");
        uint48 transition = _task.lastTransitionAt();
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(_core), probe, abi.encode(false));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizerTask_InvalidCore.selector,
                address(_core)
            )
        );
        _task.enable("");
        assertFalse(_task.isEnabled(), "Incompatible Core leaves consumer paused");
        assertEq(_task.lastTransitionAt(), transition, "Rejection preserves transition time");
        vm.clearMockedCalls();
        _task.enable("");
        assertTrue(_task.isEnabled(), "Restored interface permits retry");
    }

    // Scenarios: BLSEIZ-ENABLE-D13.
    function test_givenRevertingCoreInterface_whenActivated_reverts() public {
        _task.disable("");
        uint48 transition = _task.lastTransitionAt();
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCallRevert(address(_core), probe, hex"deadbeef");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizerTask_InvalidCore.selector,
                address(_core)
            )
        );
        _task.enable("");
        assertFalse(_task.isEnabled(), "Incompatible Core leaves consumer paused");
        assertEq(_task.lastTransitionAt(), transition, "Rejection preserves transition time");
        vm.clearMockedCalls();
        _task.enable("");
        assertTrue(_task.isEnabled(), "Restored interface permits retry");
    }

    // Scenarios: BLSEIZ-ENABLE-D14.
    function test_givenMalformedCoreInterface_whenActivated_reverts() public {
        _task.disable("");
        uint48 transition = _task.lastTransitionAt();
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(_core), probe, hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansSeizerTask.BurnerLoansSeizerTask_InvalidCore.selector,
                address(_core)
            )
        );
        _task.enable("");
        assertFalse(_task.isEnabled(), "Incompatible Core leaves consumer paused");
        assertEq(_task.lastTransitionAt(), transition, "Rejection preserves transition time");
        vm.clearMockedCalls();
        _task.enable("");
        assertTrue(_task.isEnabled(), "Restored interface permits retry");
    }

    // Scenarios: BLSEIZ-ENABLE-P10.
    function test_givenCoreLifecycle_whenActivated(bool active_, bool enabled_) public {
        _task.disable("");
        _setCoreLifecycle(active_, enabled_);
        _task.enable("");
        assertTrue(
            _task.isEnabled(),
            "Core lifecycle does not gate compatible consumer activation"
        );
    }

    // Scenarios: BLSEIZ-ENABLE-P10.
    function test_whenCoreLifecycleStatesSeeded_thenActivated() public {
        uint256 snapshot = vm.snapshotState();
        test_givenCoreLifecycle_whenActivated(false, false);
        assertTrue(vm.revertToState(snapshot), "Restore disabled inactive Core");
        test_givenCoreLifecycle_whenActivated(false, true);
        assertTrue(vm.revertToState(snapshot), "Restore enabled inactive Core");
        test_givenCoreLifecycle_whenActivated(true, false);
        assertTrue(vm.revertToState(snapshot), "Restore disabled active Core");
        test_givenCoreLifecycle_whenActivated(true, true);
        assertTrue(vm.revertToStateAndDelete(snapshot), "Restore enabled active Core");
    }
}
